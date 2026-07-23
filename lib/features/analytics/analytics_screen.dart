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

/// Which section is on screen. Only the selected one is built, so hidden charts
/// cost nothing (TODO 7.6 / 8.8).
enum _Section {
  cashFlow('Cash flow'),
  spending('Spending'),
  daily('Daily'),
  netWorth('Net worth'),
  lists('Lists');

  const _Section(this.label);
  final String label;
}

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
  _Section _section = _Section.cashFlow;

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(analyticsQueryProvider);
    final bundleAsync = ref.watch(analyticsProvider);

    return NewsprintPage(
      kicker: 'Analytics',
      title: 'Where the money went',
      subtitle:
          'Curated charts, one period selector. Every figure reconciles to the '
          'ledger it links to, with spending shown as pies.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PeriodBar(query: query),
          const SizedBox(height: 8),
          _SectionBar(
            section: _section,
            onSelected: (s) => setState(() => _section = s),
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
        // Only the active section is constructed.
        switch (_section) {
          _Section.cashFlow => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                OutflowMixPieChart(mix: bundle.outflowMix),
              ],
            ),
          _Section.spending => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LabelSpendChart(
                  slices: bundle.byLabel,
                  includeFamily: bundle.includeFamilySupport,
                  onLabelTap: (slice) => _drillToLabel(slice),
                  onReviewTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ReviewQueueScreen()),
                  ),
                ),
                const SizedBox(height: 22),
                OutflowMixPieChart(mix: bundle.outflowMix),
              ],
            ),
          _Section.daily => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DailyCumulativeChart(
                  points: bundle.dailySpend,
                  onDayTap: _drillToDay,
                ),
                const SizedBox(height: 22),
                DailySpendDeltaChart(points: bundle.dailySpend),
              ],
            ),
          _Section.netWorth => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NetWorthChart(
                  points: bundle.netWorth,
                  current: bundle.netWorthCurrent,
                ),
                const SizedBox(height: 22),
                NetWorthChangeChart(changes: bundle.netWorthChanges),
              ],
            ),
          _Section.lists => _Lists(bundle: bundle),
        },
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
    final months =
        ref.read(analyticsQueryProvider).period.monthsAsOf(DateTime.now());
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - (months - 1), 1);
    _apply(LedgerQuery(labelId: slice.labelId, from: from, type: 'debit'));
  }

  void _drillToDay(int day) {
    final now = DateTime.now();
    if (day > now.day) return;
    final date = DateTime(now.year, now.month, day);
    _apply(LedgerQuery(from: date, to: date, type: 'debit'));
  }
}

class _PeriodBar extends ConsumerWidget {
  const _PeriodBar({required this.query});

  final AnalyticsQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.section, required this.onSelected});

  final _Section section;
  final ValueChanged<_Section> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final s in _Section.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(s.label),
                selected: section == s,
                onSelected: (_) => onSelected(s),
              ),
            ),
        ],
      ),
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
