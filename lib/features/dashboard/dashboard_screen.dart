import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dashboard_analytics.dart';
import '../../core/theme.dart';
import '../../models/goal.dart';
import '../../models/transaction.dart';
import '../../providers/account_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/transaction_provider.dart';

final currencyFormat =
    NumberFormat.currency(symbol: '\u20B9', decimalDigits: 0, locale: 'en_IN');
final compactCurrencyFormat = NumberFormat.compactCurrency(
    symbol: '\u20B9', decimalDigits: 1, locale: 'en_IN');
final monthLabelFormat = DateFormat('MMM');
final monthTitleFormat = DateFormat('MMMM yyyy');
final syncLabelFormat = DateFormat('dd MMM, HH:mm');

const _chartColors = [
  AppTheme.primaryGreen,
  AppTheme.redAccent,
  AppTheme.accentPurple,
  AppTheme.accentGold,
  Colors.cyanAccent,
  Colors.orangeAccent,
  Colors.pinkAccent,
  Colors.lightBlueAccent,
];

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(accountProvider);
    ref.invalidate(accountBalancesProvider);
    ref.invalidate(netWorthProvider);
    ref.invalidate(goalProvider);
    await ref.read(transactionProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionProvider);
    final goalsAsync = ref.watch(goalProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: transactionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          error: '$error',
          onRetry: _refresh,
        ),
        data: (transactions) {
          final goals = goalsAsync.maybeWhen(
            data: (items) => items,
            orElse: () => <Goal>[],
          );
          return _DashboardContent(
            transactions: transactions,
            goals: goals,
            onRefresh: _refresh,
          );
        },
      ),
    );
  }
}

class _DashboardContent extends ConsumerStatefulWidget {
  const _DashboardContent({
    required this.transactions,
    required this.goals,
    required this.onRefresh,
  });

  final List<Transaction> transactions;
  final List<Goal> goals;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends ConsumerState<_DashboardContent> {
  DateTime? _selectedMonth;

  DateTime _resolvedSelectedMonth(List<DateTime> availableMonths) {
    if (_selectedMonth != null &&
        availableMonths.any((month) => _isSameMonth(month, _selectedMonth!))) {
      return DateTime(_selectedMonth!.year, _selectedMonth!.month);
    }

    if (availableMonths.isEmpty) {
      final now = DateTime.now();
      return DateTime(now.year, now.month);
    }

    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final previousMonth = DateTime(now.year, now.month - 1);

    if (now.day <= 7 &&
        availableMonths.any((month) => _isSameMonth(month, previousMonth))) {
      return previousMonth;
    }
    if (availableMonths.any((month) => _isSameMonth(month, currentMonth))) {
      return currentMonth;
    }
    return availableMonths.first;
  }

  bool _isSameMonth(DateTime left, DateTime right) =>
      left.year == right.year && left.month == right.month;

  @override
  Widget build(BuildContext context) {
    final availableMonths =
        DashboardAnalytics.monthsForTransactions(widget.transactions);
    final selectedMonth = _resolvedSelectedMonth(availableMonths);
    final analytics = DashboardAnalytics.fromTransactions(
      widget.transactions,
      focusMonth: selectedMonth,
    );
    final summary = analytics.currentMonth;
    final sortedGoals = [...widget.goals]..sort((a, b) {
        if (a.isEmergencyFund == b.isEmergencyFund) {
          return a.name.compareTo(b.name);
        }
        return a.isEmergencyFund ? -1 : 1;
      });

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PeriodSelector(
            selectedMonth: selectedMonth,
            availableMonths: analytics.availableMonths,
            onChanged: (month) => setState(() => _selectedMonth = month),
          ),
          const SizedBox(height: 16),
          _SnapshotHeroCard(
            summary: summary,
            latestTransactionAt: analytics.latestTransactionAt,
          ),
          const SizedBox(height: 16),
          _MetricGrid(summary: summary),
          const SizedBox(height: 24),
          const _AccountBalancesSection(),
          const SizedBox(height: 24),
          _SectionCard(
            title: 'Income vs Spending',
            subtitle:
                'Six-month trend ending in ${monthTitleFormat.format(selectedMonth)}',
            child: _MonthlyTrendChart(points: analytics.monthlyTrend),
          ),
          const SizedBox(height: 24),
          _SectionCard(
            title: 'Daily Activity',
            subtitle:
                'Daily income and spending movements for ${monthTitleFormat.format(selectedMonth)}',
            child: _DailyFlowChart(points: analytics.dailyFlow),
          ),
          const SizedBox(height: 24),
          _SectionCard(
            title: 'Spending Mix',
            subtitle: summary.uncategorizedCount > 0
                ? 'Uncategorized transactions are included so hidden spend stays visible'
                : 'Spending split by category for ${monthTitleFormat.format(selectedMonth)}',
            child: _CategoryBreakdown(categories: analytics.spendingCategories),
          ),
          const SizedBox(height: 24),
          _GoalTrackersSection(goals: sortedGoals),
          const SizedBox(height: 24),
          _ActionItemsSection(
            analytics: analytics,
            hasEmergencyFund: widget.goals.any((goal) => goal.isEmergencyFund),
          ),
        ],
      ),
    );
  }
}

class _SnapshotHeroCard extends StatelessWidget {
  const _SnapshotHeroCard({
    required this.summary,
    required this.latestTransactionAt,
  });

  final DashboardPeriodSummary summary;
  final DateTime? latestTransactionAt;

  @override
  Widget build(BuildContext context) {
    final paceColor =
        summary.projectedSpending <= summary.income || summary.income == 0
            ? AppTheme.primaryGreen
            : AppTheme.redAccent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [AppTheme.darkCard, AppTheme.darkSurface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: AppTheme.accentGold),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      monthTitleFormat.format(summary.month),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currencyFormat.format(summary.savings),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: summary.savings >= 0
                            ? AppTheme.primaryGreen
                            : AppTheme.redAccent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Net savings in selected month',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              _Badge(
                icon: summary.savingsRate >= 20
                    ? Icons.trending_up_rounded
                    : Icons.warning_amber_rounded,
                label: '${summary.savingsRate.toStringAsFixed(0)}% rate',
                color: summary.savingsRate >= 20
                    ? AppTheme.primaryGreen
                    : AppTheme.redAccent,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatPill(
                label: 'Tracked',
                value: '${summary.transactionCount} txns',
              ),
              _StatPill(
                label: 'Categorized',
                value:
                    '${(summary.categorizedRatio * 100).toStringAsFixed(0)}%',
              ),
              _StatPill(
                label: 'Daily avg spend',
                value:
                    compactCurrencyFormat.format(summary.averageDailySpending),
              ),
              _StatPill(
                label: 'Projected spend',
                value: compactCurrencyFormat.format(summary.projectedSpending),
                valueColor: paceColor,
              ),
            ],
          ),
          if (latestTransactionAt != null) ...[
            const SizedBox(height: 14),
            Text(
              'Latest transaction: ${syncLabelFormat.format(latestTransactionAt!.toLocal())}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.selectedMonth,
    required this.availableMonths,
    required this.onChanged,
  });

  final DateTime selectedMonth;
  final List<DateTime> availableMonths;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    if (availableMonths.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedIndex = availableMonths.indexWhere(
      (month) =>
          month.year == selectedMonth.year &&
          month.month == selectedMonth.month,
    );
    final newerMonth =
        selectedIndex > 0 ? availableMonths[selectedIndex - 1] : null;
    final olderMonth =
        selectedIndex >= 0 && selectedIndex < availableMonths.length - 1
            ? availableMonths[selectedIndex + 1]
            : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(14)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: newerMonth == null ? null : () => onChanged(newerMonth),
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Newer month',
          ),
          Expanded(
            child: Center(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<DateTime>(
                  value: availableMonths.firstWhere(
                    (month) =>
                        month.year == selectedMonth.year &&
                        month.month == selectedMonth.month,
                  ),
                  alignment: Alignment.center,
                  dropdownColor: AppTheme.darkSurface,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  items: availableMonths
                      .map(
                        (month) => DropdownMenuItem<DateTime>(
                          value: month,
                          child: Text(monthTitleFormat.format(month)),
                        ),
                      )
                      .toList(),
                  onChanged: (month) {
                    if (month != null) onChanged(month);
                  },
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: olderMonth == null ? null : () => onChanged(olderMonth),
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Older month',
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.summary});

  final DashboardPeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth >= 720
            ? (constraints.maxWidth - 36) / 4
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'Earned',
                amount: currencyFormat.format(summary.income),
                icon: Icons.arrow_downward_rounded,
                color: AppTheme.primaryGreen,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'Spent',
                amount: currencyFormat.format(summary.spending),
                icon: Icons.arrow_upward_rounded,
                color: AppTheme.redAccent,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'Saved',
                amount: currencyFormat.format(summary.savings),
                icon: Icons.savings_outlined,
                color: summary.savings >= 0
                    ? AppTheme.primaryGreen
                    : AppTheme.redAccent,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'Invested',
                amount: currencyFormat.format(summary.investments),
                icon: Icons.show_chart_rounded,
                color: AppTheme.accentPurple,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final String label;
  final String amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            amount,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountBalancesSection extends ConsumerWidget {
  const _AccountBalancesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountProvider);
    final balancesAsync = ref.watch(accountBalancesProvider);
    final netWorthAsync = ref.watch(netWorthProvider);

    return accountsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (accounts) {
        if (accounts.isEmpty) return const SizedBox.shrink();
        final balances = balancesAsync.maybeWhen(
          data: (items) => items,
          orElse: () => <String, double>{},
        );
        final netWorth = netWorthAsync.maybeWhen(
          data: (value) => value,
          orElse: () => 0,
        );
        return _SectionCard(
          title: 'Net Worth & Accounts',
          subtitle: 'Derived from account balances and ledger transactions',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currencyFormat.format(netWorth),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: accounts.map((account) {
                  final balance = balances[account.id] ?? 0;
                  return _AccountChip(
                    name: account.name,
                    balance: balance,
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MonthlyTrendChart extends StatelessWidget {
  const _MonthlyTrendChart({required this.points});

  final List<DashboardMonthlyPoint> points;

  @override
  Widget build(BuildContext context) {
    final hasData = points.any(
      (point) => point.income > 0 || point.spending > 0 || point.savings != 0,
    );
    if (!hasData) {
      return const _ChartEmptyState(message: 'No multi-month activity yet');
    }

    final values = <double>[
      for (final point in points) point.income,
      for (final point in points) point.spending,
      for (final point in points) point.savings,
    ];
    final minValue = values.reduce(min);
    final maxValue = values.reduce(max);
    final minY = minValue < 0 ? minValue * 1.2 : 0.0;
    final maxY = maxValue == 0 ? 1.0 : maxValue * 1.2;

    return SizedBox(
      height: 280,
      child: Column(
        children: [
          Expanded(
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: max(0, points.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: _niceInterval(maxY - minY),
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withAlpha(18),
                    strokeWidth: 1,
                  ),
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= points.length) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            monthLabelFormat.format(points[index].month),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          compactCurrencyFormat.format(value),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                lineBarsData: [
                  _lineSeries(
                    points: points,
                    color: AppTheme.primaryGreen,
                    selector: (point) => point.income,
                  ),
                  _lineSeries(
                    points: points,
                    color: AppTheme.redAccent,
                    selector: (point) => point.spending,
                  ),
                  _lineSeries(
                    points: points,
                    color: AppTheme.accentPurple,
                    selector: (point) => point.savings,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LegendChip(label: 'Income', color: AppTheme.primaryGreen),
              _LegendChip(label: 'Spending', color: AppTheme.redAccent),
              _LegendChip(label: 'Savings', color: AppTheme.accentPurple),
            ],
          ),
        ],
      ),
    );
  }

  LineChartBarData _lineSeries({
    required List<DashboardMonthlyPoint> points,
    required Color color,
    required double Function(DashboardMonthlyPoint point) selector,
  }) {
    return LineChartBarData(
      isCurved: true,
      color: color,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
          radius: 3,
          color: color,
          strokeWidth: 1,
          strokeColor: Colors.white,
        ),
      ),
      belowBarData: BarAreaData(show: false),
      spots: [
        for (var index = 0; index < points.length; index++)
          FlSpot(index.toDouble(), selector(points[index])),
      ],
    );
  }
}

class _DailyFlowChart extends StatelessWidget {
  const _DailyFlowChart({required this.points});

  final List<DashboardDailyPoint> points;

  @override
  Widget build(BuildContext context) {
    final hasData =
        points.any((point) => point.income > 0 || point.spending > 0);
    if (!hasData) {
      return const _ChartEmptyState(message: 'No daily activity this month');
    }

    final maxValue =
        points.map((point) => max(point.income, point.spending)).reduce(max);
    final maxY = maxValue == 0 ? 1.0 : maxValue * 1.25;

    return SizedBox(
      height: 290,
      child: Column(
        children: [
          Expanded(
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceBetween,
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: _niceInterval(maxY),
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withAlpha(18),
                    strokeWidth: 1,
                  ),
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          compactCurrencyFormat.format(value),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= points.length) {
                          return const SizedBox.shrink();
                        }
                        final day = points[index].day.day;
                        if (day != 1 &&
                            day != points.last.day.day &&
                            day % 5 != 0) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            '$day',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var index = 0; index < points.length; index++)
                    BarChartGroupData(
                      x: index,
                      barsSpace: 4,
                      barRods: [
                        BarChartRodData(
                          toY: points[index].spending,
                          width: 6,
                          color: AppTheme.redAccent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        BarChartRodData(
                          toY: points[index].income,
                          width: 6,
                          color: AppTheme.primaryGreen,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LegendChip(label: 'Daily spend', color: AppTheme.redAccent),
              _LegendChip(label: 'Daily income', color: AppTheme.primaryGreen),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.categories});

  final List<DashboardCategoryPoint> categories;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const _ChartEmptyState(message: 'No spending recorded this month');
    }

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 44,
              sectionsSpace: 3,
              sections: [
                for (var index = 0; index < categories.length; index++)
                  PieChartSectionData(
                    value: categories[index].amount,
                    color: _chartColors[index % _chartColors.length],
                    title:
                        '${(categories[index].share * 100).toStringAsFixed(0)}%',
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    radius: 58,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(categories.length, (index) {
          final category = categories[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _chartColors[index % _chartColors.length],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    category.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${(category.share * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  currencyFormat.format(category.amount),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _GoalTrackersSection extends StatelessWidget {
  const _GoalTrackersSection({required this.goals});

  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    if (goals.isEmpty) {
      return const _SectionCard(
        title: 'Goal Trackers',
        subtitle: 'No savings goals yet',
        child: _ChartEmptyState(
          message:
              'Create a goal to track an emergency fund, device purchase, or other target',
        ),
      );
    }

    return _SectionCard(
      title: 'Goal Trackers',
      subtitle: 'Progress against saved targets',
      child: Column(
        children: goals.map((goal) => _GoalProgressTile(goal: goal)).toList(),
      ),
    );
  }
}

class _GoalProgressTile extends StatelessWidget {
  const _GoalProgressTile({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final remaining = max(0.0, goal.targetAmount - goal.allocatedAmount);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  goal.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (goal.isEmergencyFund)
                const _Badge(
                  icon: Icons.shield_outlined,
                  label: 'Emergency fund',
                  color: AppTheme.primaryGreen,
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (goal.fundedPercent / 100).clamp(0.0, 1.0),
              minHeight: 12,
              backgroundColor: AppTheme.darkBg,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.accentGold),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${currencyFormat.format(goal.allocatedAmount)} saved',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              Text(
                '${goal.fundedPercent.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accentGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Remaining ${currencyFormat.format(remaining)} of ${currencyFormat.format(goal.targetAmount)}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionItemsSection extends StatelessWidget {
  const _ActionItemsSection({
    required this.analytics,
    required this.hasEmergencyFund,
  });

  final DashboardAnalytics analytics;
  final bool hasEmergencyFund;

  @override
  Widget build(BuildContext context) {
    final summary = analytics.currentMonth;
    final items = <_ActionItemData>[];

    if (summary.uncategorizedCount > 0) {
      items.add(
        _ActionItemData(
          icon: Icons.label_off_outlined,
          color: AppTheme.accentGold,
          title: 'Categorize recent spending',
          message:
              '${summary.uncategorizedCount} selected-month transactions are still uncategorized, so category insights are less accurate than they should be.',
        ),
      );
    }

    if (!hasEmergencyFund) {
      items.add(
        const _ActionItemData(
          icon: Icons.shield_outlined,
          color: AppTheme.primaryGreen,
          title: 'Add an emergency fund goal',
          message:
              'A dedicated emergency fund tracker keeps cash safety separate from discretionary goals like gadgets or travel.',
        ),
      );
    }

    if (summary.income > 0 && summary.projectedSpending > summary.income) {
      items.add(
        _ActionItemData(
          icon: Icons.speed_rounded,
          color: AppTheme.redAccent,
          title: 'Spending pace is running hot',
          message:
              'At the current daily pace, projected spending is ${currencyFormat.format(summary.projectedSpending)}, which is above the selected month\'s income.',
        ),
      );
    } else if (summary.income > 0) {
      items.add(
        _ActionItemData(
          icon: Icons.trending_up_rounded,
          color: AppTheme.primaryGreen,
          title: 'Savings pace is healthy',
          message:
              'Projected spending is ${currencyFormat.format(summary.projectedSpending)} against income of ${currencyFormat.format(summary.income)}.',
        ),
      );
    }

    if (items.isEmpty) {
      items.add(
        const _ActionItemData(
          icon: Icons.check_circle_outline,
          color: AppTheme.primaryGreen,
          title: 'Dashboard is in good shape',
          message:
              'Keep classifying transactions and adding savings goals to make long-term charts more useful.',
        ),
      );
    }

    return _SectionCard(
      title: 'Action Items',
      subtitle: 'What needs attention based on current data',
      child: Column(
        children: items.map((item) => _ActionItemTile(item: item)).toList(),
      ),
    );
  }
}

class _ActionItemTile extends StatelessWidget {
  const _ActionItemTile({required this.item});

  final _ActionItemData item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: item.color.withAlpha(28),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, color: item.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.message,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionItemData {
  const _ActionItemData({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withAlpha(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.name, required this.balance});

  final String name;
  final double balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            currencyFormat.format(balance),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartEmptyState extends StatelessWidget {
  const _ChartEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.redAccent),
          const SizedBox(height: 16),
          Text(error, style: const TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

double _niceInterval(double range) {
  if (range <= 0) return 1;
  final rough = range / 4;
  if (rough <= 1000) return 500;
  if (rough <= 5000) return 1000;
  if (rough <= 10000) return 2500;
  if (rough <= 25000) return 5000;
  return 10000;
}
