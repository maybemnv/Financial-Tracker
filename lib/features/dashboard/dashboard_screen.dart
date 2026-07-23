import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/aggregates.dart';
import '../../core/theme.dart';
import '../../models/goal.dart';
import '../../providers/account_provider.dart';
import '../../providers/aggregate_provider.dart';
import '../../providers/goal_provider.dart';
import '../../widgets/newsprint_primitives.dart';
import '../analytics/obligations_view.dart';
import '../labels/review_queue_screen.dart';

final currencyFormat =
    NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
final monthTitleFormat = DateFormat('MMMM yyyy');

/// Briefing — numbers only (Phase 8.1).
///
/// Every figure comes from `get_briefing_summary`, one owner-scoped call. The
/// monthly trend line, daily bar chart, and label pie that used to live here
/// are gone; their replacements are the four Analytics charts. That also
/// removed the last screen pulling the whole ledger into memory to render (D4).
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    ref.invalidate(briefingSummaryProvider);
    ref.invalidate(accountProvider);
    ref.invalidate(accountBalancesProvider);
    ref.invalidate(netWorthProvider);
    ref.invalidate(goalProvider);
  }

  @override
  Widget build(BuildContext context) {
    final period = (year: _selectedMonth.year, month: _selectedMonth.month);
    final summaryAsync = ref.watch(briefingSummaryProvider(period));

    return NewsprintPage(
      kicker: 'Briefing',
      title: 'Monthly money briefing',
      subtitle: 'Cashflow, balances, and problem spots for the selected month. '
          'Use the month rail to inspect earlier or later periods.',
      child: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: NewsprintNotice(
            icon: Icons.error_outline_rounded,
            title: 'Briefing unavailable',
            message: '$error',
            color: AppTheme.redAccent,
          ),
        ),
        data: (summary) => RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _MonthRail(
                month: _selectedMonth,
                onPrevious: () => setState(() {
                  _selectedMonth = DateTime(
                    _selectedMonth.year,
                    _selectedMonth.month - 1,
                  );
                }),
                onNext: () => setState(() {
                  _selectedMonth = DateTime(
                    _selectedMonth.year,
                    _selectedMonth.month + 1,
                  );
                }),
                onPick: _pickMonth,
              ),
              const SizedBox(height: 12),
              _StatusLine(summary: summary),
              const SizedBox(height: 12),
              _MetricGrid(summary: summary),
              const SizedBox(height: 16),
              const NewsprintSectionTitle(label: 'Accounts'),
              const SizedBox(height: 8),
              const _AccountBalances(),
              const SizedBox(height: 16),
              const NewsprintSectionTitle(label: 'Goals'),
              const SizedBox(height: 8),
              const _GoalProgress(),
              const SizedBox(height: 16),
              const NewsprintSectionTitle(label: 'Upcoming'),
              const SizedBox(height: 8),
              const ObligationsList(limit: 4),
              const SizedBox(height: 12),
              const ForecastCard(compact: true),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickMonth() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _MonthPickerDialog(initialMonth: _selectedMonth),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedMonth = picked);
  }
}

class _MonthRail extends StatelessWidget {
  const _MonthRail({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final canGoBack = month.year > 1970 || month.month > 1;
    final canGoForward = month.year < 2100 || month.month < 12;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: AppTheme.panelDecoration(color: AppTheme.paperAlt),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          return Row(
            children: [
              if (compact)
                IconButton.outlined(
                  onPressed: canGoBack ? onPrevious : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: 'Previous month',
                )
              else
                OutlinedButton.icon(
                  onPressed: canGoBack ? onPrevious : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('BACK'),
                ),
              Expanded(
                child: Center(
                  child: TextButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text(
                      monthTitleFormat.format(month),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
              ),
              if (compact)
                IconButton.outlined(
                  onPressed: canGoForward ? onNext : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'Next month',
                )
              else
                OutlinedButton.icon(
                  onPressed: canGoForward ? onNext : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('NEXT'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.initialMonth});

  final DateTime initialMonth;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _month;
  late int _year;

  @override
  void initState() {
    super.initState();
    _month = widget.initialMonth.month;
    _year = widget.initialMonth.year;
  }

  @override
  Widget build(BuildContext context) {
    final years = [for (var y = 1970; y <= 2100; y++) y];

    return AlertDialog(
      title: const Text('Pick month'),
      content: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _month,
              decoration: const InputDecoration(labelText: 'Month'),
              items: [
                for (var m = 1; m <= 12; m++)
                  DropdownMenuItem(
                    value: m,
                    child: Text(DateFormat.MMMM().format(DateTime(2026, m))),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _month = value);
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 116,
            child: DropdownButtonFormField<int>(
              initialValue: _year,
              decoration: const InputDecoration(labelText: 'Year'),
              items: [
                for (final y in years)
                  DropdownMenuItem(value: y, child: Text('$y')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _year = value);
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, DateTime(_year, _month)),
          child: const Text('APPLY'),
        ),
      ],
    );
  }
}

/// One concise status message plus the review backlog — the only thing on this
/// screen the owner can act on directly.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.summary});

  final BriefingSummary summary;

  @override
  Widget build(BuildContext context) {
    final period = DateTime(summary.year, summary.month);
    final surplus = summary.netCashSurplus;
    final message = surplus >= 0
        ? 'Income covers outflow this month with '
            '${currencyFormat.format(surplus)} spare.'
        : 'Outflow exceeds income by ${currencyFormat.format(-surplus)} '
            'this month.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(monthTitleFormat.format(period),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(message, style: Theme.of(context).textTheme.bodyMedium),
        if (!summary.reconciles)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: NewsprintNotice(
              icon: Icons.warning_amber_rounded,
              title: 'Figures do not reconcile',
              message: 'Total Outflow should equal Personal Spend plus Family '
                  'Support. It does not, so treat these numbers as suspect and '
                  're-check before acting on them.',
              color: AppTheme.redAccent,
            ),
          ),
        if (summary.needsPrimaryCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReviewQueueScreen()),
              ),
              child: Text(
                '${summary.needsPrimaryCount} expense'
                '${summary.needsPrimaryCount == 1 ? '' : 's'} '
                'not attributed to any category — review',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.redAccent),
              ),
            ),
          ),
      ],
    );
  }
}

/// The canonical PRD §4 metrics. Wording matters: Family Support has left the
/// accounts too, so nothing here calls it money kept.
class _MetricGrid extends ConsumerWidget {
  const _MetricGrid({required this.summary});

  final BriefingSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netWorth = ref.watch(netWorthProvider);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        NewsprintMetricStrip(
            label: 'Income', value: currencyFormat.format(summary.income)),
        NewsprintMetricStrip(
            label: 'Total Outflow',
            value: currencyFormat.format(summary.totalOutflow)),
        NewsprintMetricStrip(
            label: 'Personal Spend',
            value: currencyFormat.format(summary.personalSpend)),
        NewsprintMetricStrip(
            label: 'Family Support',
            value: currencyFormat.format(summary.familySupport)),
        NewsprintMetricStrip(
          label: 'Net Cash Surplus',
          value: currencyFormat.format(summary.netCashSurplus),
          valueColor: summary.netCashSurplus < 0 ? AppTheme.redAccent : null,
        ),
        NewsprintMetricStrip(
            label: 'Savings Rate',
            value: '${summary.savingsRate.toStringAsFixed(1)}%'),
        NewsprintMetricStrip(
          label: 'Net Worth',
          value: netWorth.when(
            data: currencyFormat.format,
            loading: () => '…',
            // Never render a failure as zero — that is a plausible wrong number.
            error: (_, __) => 'unavailable',
          ),
        ),
      ],
    );
  }
}

class _AccountBalances extends ConsumerWidget {
  const _AccountBalances();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountProvider).valueOrNull ?? const [];
    final balances = ref.watch(accountBalancesProvider);

    return balances.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Balances unavailable: $e',
          style: Theme.of(context).textTheme.bodySmall),
      data: (map) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final account in accounts)
            if (account.id != null)
              NewsprintMetricStrip(
                label: account.name,
                value: currencyFormat.format(map[account.id] ?? 0),
              ),
        ],
      ),
    );
  }
}

class _GoalProgress extends ConsumerWidget {
  const _GoalProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalProvider).valueOrNull ?? const <Goal>[];
    final active = goals.where((g) => !g.isArchived).toList();
    if (active.isEmpty) {
      return Text('No goals yet.',
          style: Theme.of(context).textTheme.bodySmall);
    }

    return Column(
      children: [
        for (final goal in active)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(goal.name,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                    Text(
                      '${currencyFormat.format(goal.allocatedAmount)}'
                      ' / ${currencyFormat.format(goal.targetAmount)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRect(
                  child: LinearProgressIndicator(
                    value: (goal.fundedPercent / 100).clamp(0, 1).toDouble(),
                    minHeight: 8,
                    backgroundColor: AppTheme.paperMuted,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      goal.isEmergencyFund ? AppTheme.redAccent : AppTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
