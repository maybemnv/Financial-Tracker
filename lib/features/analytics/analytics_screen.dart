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

/// Analytics — exactly four primary charts, each with a typed source, an
/// accessible alternative, and a drill-down that reconciles to the value shown.
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
          'Four charts, one period selector. Every figure reconciles to the '
          'ledger it links to.',
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
              data: (bundle) => ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Only the active section is constructed.
                  switch (_section) {
                    _Section.cashFlow => CashFlowChart(
                        points: bundle.cashFlow,
                        onMonthTap: (point, income) => _drillToMonth(
                          point.year,
                          point.month,
                          income ? 'credit' : 'debit',
                        ),
                      ),
                    _Section.spending => LabelSpendChart(
                        slices: bundle.byLabel,
                        includeFamily: bundle.includeFamilySupport,
                        onLabelTap: (slice) => _drillToLabel(slice),
                        onReviewTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ReviewQueueScreen()),
                        ),
                      ),
                    _Section.daily => DailyCumulativeChart(
                        points: bundle.dailySpend,
                        onDayTap: _drillToDay,
                      ),
                    _Section.netWorth => NetWorthChart(
                        points: bundle.netWorth,
                        current: bundle.netWorthCurrent,
                      ),
                    _Section.lists => _Lists(bundle: bundle),
                  },
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
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
class _Lists extends StatelessWidget {
  const _Lists({required this.bundle});

  final AnalyticsBundle bundle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NewsprintSectionTitle(label: 'Top merchants'),
        const SizedBox(height: 6),
        if (bundle.topMerchants.isEmpty)
          Text('No spending in this period.',
              style: Theme.of(context).textTheme.bodySmall)
        else
          ...bundle.topMerchants.map(
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
        const NewsprintSectionTitle(label: 'Recurring obligations'),
        const SizedBox(height: 6),
        Text(
          'Arrives with Phase 9. Merchant names are raw until Phase 10 '
          'normalizes them, so the same shop may appear more than once above.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
