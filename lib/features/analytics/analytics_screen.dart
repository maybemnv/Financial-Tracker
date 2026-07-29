import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/analytics_types.dart';
import '../../core/ledger_query.dart';
import '../../core/theme.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../widgets/newsprint_primitives.dart';
import '../labels/review_queue_screen.dart';
import 'analytics_charts.dart';
import 'merchant_alias_sheet.dart';
import 'obligations_view.dart';

final _currency =
    NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');

/// Analytics — curated chart sections, each with a typed source, an accessible
/// alternative, and drill-downs that reconcile to the value shown.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key, this.onDrillDown});

  /// Switches the app to the Ledger tab after applying a filter.
  final VoidCallback? onDrillDown;

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  @override
  Widget build(BuildContext context) {
    final query = ref.watch(analyticsQueryProvider);
    final bundleAsync = ref.watch(analyticsProvider);
    final selectedMonth = query.monthAsOf(DateTime.now());

    return NewsprintPage(
      kicker: 'Analytics',
      title: 'Where the money went',
      subtitle:
          'Every chart in one scroll, with one month selector and ledger-backed '
          'drill-downs for the numbers behind each figure.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PeriodBar(
            query: query,
            month: selectedMonth,
            onPrevious: () => _setMonth(DateTime(
              selectedMonth.year,
              selectedMonth.month - 1,
            )),
            onNext: () => _setMonth(DateTime(
              selectedMonth.year,
              selectedMonth.month + 1,
            )),
            onPick: () => _pickMonth(selectedMonth),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: bundleAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: NewsprintNotice(
                  icon: Icons.error_outline_rounded,
                  title: 'Analytics unavailable',
                  message: '$e',
                  color: AppTheme.redAccent,
                ),
              ),
              data: (bundle) => _buildCharts(
                context,
                bundle,
                bundleAsync.isRefreshing || bundleAsync.isReloading,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharts(
    BuildContext context,
    AnalyticsBundle bundle,
    bool isUpdating,
  ) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        CashFlowChart(
          points: bundle.cashFlow,
          onMonthTap: (point, income) => _drillToMonth(
            point.year,
            point.month,
            income ? 'credit' : 'debit',
          ),
        ),
        const SizedBox(height: 22),
        MonthlyNetChart(points: bundle.cashFlow),
        const SizedBox(height: 22),
        LabelSpendChart(
          slices: bundle.byLabel,
          includeFamily: bundle.includeFamilySupport,
          onLabelTap: (slice) => _drillToLabel(slice),
          onReviewTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ReviewQueueScreen()),
          ),
        ),
        const SizedBox(height: 22),
        OutflowMixPieChart(mix: bundle.outflowMix),
        const SizedBox(height: 22),
        DailyCumulativeChart(
          points: bundle.dailySpend,
          onDayTap: _drillToDay,
        ),
        const SizedBox(height: 22),
        DailySpendDeltaChart(points: bundle.dailySpend),
        const SizedBox(height: 22),
        NetWorthChart(
          points: bundle.netWorth,
          current: bundle.netWorthCurrent,
        ),
        const SizedBox(height: 22),
        NetWorthChangeChart(changes: bundle.netWorthChanges),
        const SizedBox(height: 22),
        _Lists(bundle: bundle),
        if (isUpdating)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _apply(LedgerQuery query) {
    ref.read(ledgerProvider.notifier).setQuery(query);
    widget.onDrillDown?.call();
  }

  void _drillToMonth(int year, int month, String type) {
    final from = DateTime(year, month, 1);
    final to = DateTime(year, month + 1, 0);
    _apply(LedgerQuery(from: from, to: to, type: type));
  }

  void _drillToLabel(LabelSpend slice) {
    if (slice.labelId == null) return;
    final now = DateTime.now();
    final query = ref.read(analyticsQueryProvider);
    final asOfMonth = query.monthAsOf(now);
    final months = query.period.monthsAsOf(asOfMonth);
    final from = DateTime(asOfMonth.year, asOfMonth.month - (months - 1), 1);
    final to = DateTime(asOfMonth.year, asOfMonth.month + 1, 0);
    _apply(
      LedgerQuery(labelId: slice.labelId, from: from, to: to, type: 'debit'),
    );
  }

  void _drillToDay(int day) {
    final now = DateTime.now();
    final query = ref.read(analyticsQueryProvider);
    final asOf = query.asOfInstant(now);
    final month = query.monthAsOf(now);
    final date = DateTime(month.year, month.month, day);
    if (date.isAfter(asOf)) return;
    _apply(LedgerQuery(from: date, to: date, type: 'debit'));
  }

  void _setMonth(DateTime month) {
    ref.read(analyticsQueryProvider.notifier).update(
          (query) => query.copyWith(
            anchorYear: month.year,
            anchorMonth: month.month,
          ),
        );
  }

  Future<void> _pickMonth(DateTime selectedMonth) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _MonthPickerDialog(initialMonth: selectedMonth),
    );
    if (picked == null || !mounted) return;
    _setMonth(picked);
  }
}

class _PeriodBar extends ConsumerWidget {
  const _PeriodBar({
    required this.query,
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  final AnalyticsQuery query;
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MonthRail(
          month: month,
          onPrevious: onPrevious,
          onNext: onNext,
          onPick: onPick,
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final period in AnalyticsPeriod.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(period.label),
                    selected: query.period == period,
                    onSelected: (_) => ref
                        .read(analyticsQueryProvider.notifier)
                        .update((q) => q.copyWith(period: period)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // The toggle changes which outflows are counted and nothing else — it
        // never alters how an expense is attributed.
        Row(
          children: [
            Switch(
              value: query.includeFamilySupport,
              onChanged: (v) => ref
                  .read(analyticsQueryProvider.notifier)
                  .update((q) => q.copyWith(includeFamilySupport: v)),
            ),
            Expanded(
              child: Text('Include Family Support in spending',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ],
    );
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
                      DateFormat('MMMM yyyy').format(month),
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

/// Non-chart companions (8.7): top merchants today; recurring obligations
/// arrive with Phase 9.
class _Lists extends ConsumerWidget {
  const _Lists({required this.bundle});

  final AnalyticsBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Alias-normalized, so the same shop under several spellings rolls up.
    final merchants =
        ref.watch(topMerchantsProvider).valueOrNull ?? bundle.topMerchants;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
                child: NewsprintSectionTitle(label: 'Top merchants')),
            TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const MerchantAliasSheet(),
              ),
              child: const Text('ALIASES'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (merchants.isEmpty)
          Text('No spending in this period.',
              style: Theme.of(context).textTheme.bodySmall)
        else
          ...merchants.map(
            (m) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(m.merchant,
                        style: Theme.of(context).textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('${m.count}×',
                      style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(width: 10),
                  Text(_currency.format(m.amount),
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        const NewsprintSectionTitle(label: 'Upcoming obligations'),
        const SizedBox(height: 6),
        const ObligationsList(),
        const SizedBox(height: 16),
        const NewsprintSectionTitle(label: '30-day forecast'),
        const SizedBox(height: 6),
        const ForecastCard(),
        const SizedBox(height: 8),
        Text(
          'Merchant names are raw until Phase 10 normalizes them, so the same '
          'shop may appear more than once above.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
