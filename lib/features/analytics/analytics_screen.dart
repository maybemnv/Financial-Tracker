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
          'A visual monthly workbench: cash flow, spending mix, daily pace, net '
          'worth, and merchant context in one ledger-backed surface.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ControlDeck(
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
                selectedMonth,
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
    DateTime selectedMonth,
    bool isUpdating,
  ) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _MonthBriefing(
          month: selectedMonth,
          bundle: bundle,
          onDrill: _drillToMonth,
        ),
        const SizedBox(height: 14),
        _SectionBand(
          label: 'Cash Movement',
          detail: 'Income, outflow, and the month\'s net result.',
          children: [
            _ChartPanel(
              code: '01 / cash in vs out',
              child: CashFlowChart(
                points: bundle.cashFlow,
                onMonthTap: (point, income) => _drillToMonth(
                  point.year,
                  point.month,
                  income ? 'credit' : 'debit',
                ),
              ),
            ),
            _ChartPanel(
              code: '02 / net pressure',
              child: MonthlyNetChart(points: bundle.cashFlow),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SectionBand(
          label: 'Spend Anatomy',
          detail: 'Every label stays visible; Family Support remains explicit.',
          children: [
            _ChartPanel(
              code: '03 / labels',
              featured: true,
              child: LabelSpendChart(
                slices: bundle.byLabel,
                includeFamily: bundle.includeFamilySupport,
                onLabelTap: (slice) => _drillToLabel(slice),
                onReviewTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReviewQueueScreen()),
                ),
              ),
            ),
            _ChartPanel(
              code: '04 / outflow split',
              child: OutflowMixPieChart(mix: bundle.outflowMix),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SectionBand(
          label: 'Daily Pace',
          detail: 'This selected month against the previous month.',
          children: [
            _ChartPanel(
              code: '05 / cumulative',
              child: DailyCumulativeChart(
                points: bundle.dailySpend,
                onDayTap: _drillToDay,
              ),
            ),
            _ChartPanel(
              code: '06 / pulses',
              child: DailySpendDeltaChart(points: bundle.dailySpend),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SectionBand(
          label: 'Balance Sheet',
          detail: 'Net worth context without estimating missing snapshots.',
          children: [
            _ChartPanel(
              code: '07 / history',
              child: NetWorthChart(
                points: bundle.netWorth,
                current: bundle.netWorthCurrent,
              ),
            ),
            _ChartPanel(
              code: '08 / monthly change',
              child: NetWorthChangeChart(changes: bundle.netWorthChanges),
            ),
          ],
        ),
        const SizedBox(height: 14),
        NewsprintPanel(
          color: AppTheme.paperAlt,
          child: _Lists(bundle: bundle),
        ),
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
    final from = DateTime(asOfMonth.year, asOfMonth.month, 1);
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

class _ControlDeck extends ConsumerWidget {
  const _ControlDeck({
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
        const SizedBox(height: 8),
        // The toggle changes which outflows are counted and nothing else — it
        // never alters how an expense is attributed.
        NewsprintPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: AppTheme.paper,
          child: Row(
            children: [
              const NewsprintTag(
                label: 'Month Scope',
                backgroundColor: AppTheme.ink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Analytics follows this selected month only.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Switch(
                value: ref.watch(analyticsQueryProvider).includeFamilySupport,
                onChanged: (v) => ref
                    .read(analyticsQueryProvider.notifier)
                    .update((q) => q.copyWith(includeFamilySupport: v)),
              ),
              Text('Family', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthBriefing extends StatelessWidget {
  const _MonthBriefing({
    required this.month,
    required this.bundle,
    required this.onDrill,
  });

  final DateTime month;
  final AnalyticsBundle bundle;
  final void Function(int year, int month, String type) onDrill;

  @override
  Widget build(BuildContext context) {
    final point = _pointForMonth();
    final net = point.net;
    final tone = net < 0 ? AppTheme.redAccent : AppTheme.primaryGreen;
    final topLabel = bundle.byLabel.isEmpty ? null : bundle.byLabel.first;
    final savingsRate = point.income == 0 ? 0 : net / point.income * 100;

    return NewsprintPanel(
      color: AppTheme.paper,
      accentTop: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final headline = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('MMMM yyyy').format(month).toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.4,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _currency.format(net),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: tone,
                      fontFamilyFallback: AppTheme.monoFallback,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                net >= 0
                    ? 'Surplus month. Income is ahead of outflow.'
                    : 'Deficit month. Outflow is ahead of income.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => onDrill(point.year, point.month, 'credit'),
                    icon: const Icon(Icons.arrow_downward_rounded, size: 17),
                    label: const Text('INCOME ROWS'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onDrill(point.year, point.month, 'debit'),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                    label: const Text('OUTFLOW ROWS'),
                  ),
                ],
              ),
            ],
          );
          final metrics = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BriefingTile(
                  label: 'Income', value: _currency.format(point.income)),
              _BriefingTile(
                label: 'Outflow',
                value: _currency.format(point.outflow),
                valueColor: AppTheme.redAccent,
              ),
              _BriefingTile(
                label: 'Personal',
                value: _currency.format(point.personalSpend),
              ),
              _BriefingTile(
                label: 'Family',
                value: _currency.format(point.familySupport),
              ),
              _BriefingTile(
                label: 'Savings rate',
                value: '${savingsRate.toStringAsFixed(1)}%',
                valueColor: savingsRate < 0 ? AppTheme.redAccent : null,
              ),
              _BriefingTile(
                label: 'Top label',
                value: topLabel == null ? '—' : topLabel.name,
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                headline,
                const SizedBox(height: 16),
                metrics,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: headline),
              const SizedBox(width: 18),
              Expanded(flex: 7, child: metrics),
            ],
          );
        },
      ),
    );
  }

  CashFlowPoint _pointForMonth() {
    for (final point in bundle.cashFlow) {
      if (point.year == month.year && point.month == month.month) return point;
    }
    return CashFlowPoint(
      year: month.year,
      month: month.month,
      income: 0,
      outflow: 0,
      familySupport: 0,
      isPartial: false,
    );
  }
}

class _BriefingTile extends StatelessWidget {
  const _BriefingTile({
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
      width: 142,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
      decoration: BoxDecoration(
        color: AppTheme.paperAlt,
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1,
                ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: valueColor ?? AppTheme.ink,
                  fontFamilyFallback: AppTheme.monoFallback,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionBand extends StatelessWidget {
  const _SectionBand({
    required this.label,
    required this.detail,
    required this.children,
  });

  final String label;
  final String detail;
  final List<_ChartPanel> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
                child: NewsprintSectionTitle(label: label, detail: detail)),
            const SizedBox(width: 8),
            Text('MONTHLY VIEW', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumn = constraints.maxWidth >= 860;
            final width = twoColumn
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final child in children)
                  SizedBox(
                    width: twoColumn && !child.featured
                        ? width
                        : constraints.maxWidth,
                    child: child,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ChartPanel extends StatelessWidget {
  const _ChartPanel({
    required this.code,
    required this.child,
    this.featured = false,
  });

  final String code;
  final Widget child;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    return NewsprintPanel(
      color: featured ? AppTheme.paper : AppTheme.paperAlt,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            code.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.inkSoft,
                  letterSpacing: 1.1,
                ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
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
