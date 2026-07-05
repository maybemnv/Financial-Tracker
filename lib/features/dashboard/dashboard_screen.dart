import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/goal.dart';
import '../../models/transaction.dart';
import '../../providers/account_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/summary_card.dart';

final currencyFormat =
    NumberFormat.currency(symbol: '₹', decimalDigits: 2, locale: 'en_IN');

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionProvider);
    final goalsAsync = ref.watch(goalProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: transactionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
          error: '$e',
          onRetry: () => ref.read(transactionProvider.notifier).load(),
        ),
        data: (transactions) {
          final emergencyFund = goalsAsync.maybeWhen(
            data: (goals) => goals.where((g) => g.isEmergencyFund).toList(),
            orElse: () => <Goal>[],
          );
          return _DashboardContent(
            transactions: transactions,
            emergencyFund: emergencyFund,
            onRefresh: () => ref.read(transactionProvider.notifier).load(),
          );
        },
      ),
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({
    required this.transactions,
    required this.emergencyFund,
    required this.onRefresh,
  });

  final List<Transaction> transactions;
  final List<Goal> emergencyFund;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final thisMonth =
        transactions.where((t) => _isSameMonth(t.effectiveDate, now)).toList();

    final earned = thisMonth
        .where((t) => t.isInflow)
        .fold(0.0, (sum, t) => sum + t.amount);
    final spent = thisMonth
        .where((t) => t.isOutflow)
        .fold(0.0, (sum, t) => sum + t.amount);
    final saved = earned - spent;
    final savingsRate = earned > 0 ? (saved / earned) * 100 : 0.0;

    final categoryMap = <String, double>{};
    for (final t
        in thisMonth.where((t) => t.isOutflow && t.category != null)) {
      categoryMap.update(t.category!, (v) => v + t.amount,
          ifAbsent: () => t.amount);
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (emergencyFund.isNotEmpty) ...[
            _EmergencyFundCard(goal: emergencyFund.first),
            const SizedBox(height: 16),
          ] else
            ..._emptyEmergencyFund(),
          _SavingsRateCard(rate: savingsRate),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SummaryCard(
                  label: 'Earned',
                  amount: currencyFormat.format(earned),
                  color: AppTheme.primaryGreen,
                  icon: Icons.arrow_downward,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SummaryCard(
                  label: 'Spent',
                  amount: currencyFormat.format(spent),
                  color: AppTheme.redAccent,
                  icon: Icons.arrow_upward,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SummaryCard(
                  label: 'Saved',
                  amount: currencyFormat.format(saved),
                  color:
                      saved >= 0 ? AppTheme.primaryGreen : AppTheme.redAccent,
                  icon: Icons.savings,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SummaryCard(
                  label: 'Net',
                  amount: currencyFormat.format(earned - spent),
                  color: AppTheme.accentPurple,
                  icon: Icons.account_balance,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _AccountBalancesSection(),
          const SizedBox(height: 24),
          const Text(
            'Spending by Category',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: categoryMap.isEmpty
                ? const Center(
                    child: Text(
                      'No spending this month',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : PieChart(
                    PieChartData(
                      sections: _buildPieSections(categoryMap),
                      centerSpaceRadius: 40,
                      sectionsSpace: 2,
                    ),
                  ),
          ),
          ...categoryMap.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _categoryColor(e.key),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.key)),
                  Text(
                    currencyFormat.format(e.value),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameMonth(DateTime date, DateTime other) =>
      date.year == other.year && date.month == other.month;

  List<Widget> _emptyEmergencyFund() {
    return [
      const Card(
        child: ListTile(
          leading: Icon(Icons.shield_outlined, color: AppTheme.textSecondary),
          title: Text('No Emergency Fund goal'),
          subtitle:
              Text('Set a goal of type "emergency_fund" to track it here'),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  List<PieChartSectionData> _buildPieSections(Map<String, double> data) {
    final total = data.values.fold(0.0, (a, b) => a + b);
    final colors = [
      AppTheme.primaryGreen,
      AppTheme.redAccent,
      AppTheme.accentPurple,
      AppTheme.accentGold,
      Colors.cyanAccent,
      Colors.orangeAccent,
      Colors.pinkAccent,
      Colors.lightBlueAccent,
    ];
    var i = 0;
    return data.entries.map((e) {
      final pct = (e.value / total * 100).toStringAsFixed(0);
      return PieChartSectionData(
        value: e.value,
        color: colors[i++ % colors.length],
        title: '$pct%',
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        radius: 50,
      );
    }).toList();
  }

  Color _categoryColor(String cat) {
    const colors = {
      'Food': AppTheme.primaryGreen,
      'Travel': Colors.cyanAccent,
      'Shopping': AppTheme.accentPurple,
      'Work': Colors.orangeAccent,
      'Family': Colors.pinkAccent,
      'Health': AppTheme.redAccent,
      'Subscriptions': Colors.lightBlueAccent,
    };
    return colors[cat] ?? AppTheme.accentGold;
  }
}

class _EmergencyFundCard extends StatelessWidget {
  const _EmergencyFundCard({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final allocated = goal.allocatedAmount;
    final target = goal.targetAmount;
    final pct = goal.fundedPercent;
    return Card(
      color: AppTheme.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield, color: AppTheme.primaryGreen),
                const SizedBox(width: 8),
                const Text(
                  'Emergency Fund',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 14,
                backgroundColor: AppTheme.darkBg,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${currencyFormat.format(allocated)} saved',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                Text(
                  'Target: ${currencyFormat.format(target)}',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SavingsRateCard extends StatelessWidget {
  const _SavingsRateCard({required this.rate});

  final double rate;

  @override
  Widget build(BuildContext context) {
    final onTrack = rate >= 20;
    return Card(
      color: AppTheme.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Savings Rate',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${rate.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color:
                          onTrack ? AppTheme.primaryGreen : AppTheme.redAccent,
                    ),
                  ),
                  Text(
                    onTrack ? 'On track (target 20%+)' : 'Below target (20%+)',
                    style: TextStyle(
                      color:
                          onTrack ? AppTheme.primaryGreen : AppTheme.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              onTrack ? Icons.trending_up : Icons.trending_down,
              color: onTrack ? AppTheme.primaryGreen : AppTheme.redAccent,
              size: 40,
            ),
          ],
        ),
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

    return accountsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (accounts) {
        if (accounts.isEmpty) return const SizedBox.shrink();
        final balances = balancesAsync.maybeWhen(
            data: (b) => b, orElse: () => <String, double>{});
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Account Balances',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: accounts.map((a) {
                final bal = balances[a.id] ?? 0;
                return _AccountChip(name: a.name, balance: bal);
              }).toList(),
            ),
          ],
        );
      },
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            currencyFormat.format(balance),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
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
