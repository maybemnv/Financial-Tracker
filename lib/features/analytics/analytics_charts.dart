import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/analytics_types.dart';
import '../../core/chart_theme.dart';
import '../../core/theme.dart';

final _currency =
    NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
final _compact = NumberFormat.compactCurrency(
    symbol: '₹', decimalDigits: 1, locale: 'en_IN');
final _monthShort = DateFormat('MMM');

/// Shared chrome for every chart: a title, an always-available table
/// alternative, and an accessible text summary.
///
/// The table is not optional. Two of the three validated series colours sit
/// just under 3:1 against the paper surface, which the palette rules allow only
/// with a relief channel — visible values or a table view. This is that channel,
/// and it doubles as the screen-reader path (8.8).
class ChartFrame extends StatefulWidget {
  const ChartFrame({
    super.key,
    required this.title,
    required this.summary,
    required this.chart,
    required this.table,
    this.legend,
    this.note,
  });

  final String title;

  /// One sentence stating what the chart shows, read aloud in place of the
  /// plot. Never "chart of spending" — it carries the actual numbers.
  final String summary;
  final Widget chart;
  final Widget table;
  final Widget? legend;
  final String? note;

  @override
  State<ChartFrame> createState() => _ChartFrameState();
}

class _ChartFrameState extends State<ChartFrame> {
  bool _showTable = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.title,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton(
              onPressed: () => setState(() => _showTable = !_showTable),
              child: Text(_showTable ? 'CHART' : 'TABLE'),
            ),
          ],
        ),
        if (widget.note != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(widget.note!,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        if (widget.legend != null && !_showTable)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: widget.legend,
          ),
        Semantics(
          label: widget.summary,
          child: _showTable
              ? widget.table
              : ExcludeSemantics(child: widget.chart),
        ),
      ],
    );
  }
}

/// Legend. Always present for two or more series, so identity never rests on
/// colour alone.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.entries});

  final List<({String label, Color color})> entries;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final e in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 10, color: e.color),
              const SizedBox(width: 6),
              // Text wears ink, never the series colour.
              Text(e.label,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: ChartTheme.labelInk)),
            ],
          ),
      ],
    );
  }
}

/// Two-column value table used as every chart's alternative view.
class ChartTable extends StatelessWidget {
  const ChartTable({
    super.key,
    required this.headers,
    required this.rows,
  });

  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text('No data for this period.',
          style: Theme.of(context).textTheme.bodySmall);
    }
    final labelStyle = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: ChartTheme.mutedInk);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        headingRowHeight: 32,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 40,
        columns: [
          for (final h in headers) DataColumn(label: Text(h, style: labelStyle)),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              for (final c in r)
                DataCell(Text(c,
                    style: Theme.of(context).textTheme.bodySmall)),
            ]),
        ],
      ),
    );
  }
}

Widget _empty(BuildContext context, String message) => SizedBox(
      height: 120,
      child: Center(
        child: Text(message, style: Theme.of(context).textTheme.bodySmall),
      ),
    );

String _monthLabel(int year, int month) =>
    _monthShort.format(DateTime(year, month));

// --- Chart 1: Monthly Cash Flow ---------------------------------------------

/// Grouped bars, Income vs Total Outflow. Personal Spend and Family Support are
/// deliberately NOT extra bars — they are components of Outflow, and drawing
/// them alongside would let a reader add them to Outflow and double-count.
class CashFlowChart extends StatelessWidget {
  const CashFlowChart({
    super.key,
    required this.points,
    this.onMonthTap,
  });

  final List<CashFlowPoint> points;
  final void Function(CashFlowPoint point, bool income)? onMonthTap;

  @override
  Widget build(BuildContext context) {
    final hasPartial = points.any((p) => p.isPartial);
    return ChartFrame(
      title: 'Monthly cash flow',
      note: hasPartial
          ? 'The lighter final bars are the current month, still in progress.'
          : null,
      summary: _summary(),
      legend: const ChartLegend(entries: [
        (label: 'Income', color: ChartTheme.series1),
        (label: 'Total Outflow', color: ChartTheme.series2),
      ]),
      table: ChartTable(
        headers: const ['Month', 'Income', 'Outflow', 'Net'],
        rows: [
          for (final p in points)
            [
              '${_monthLabel(p.year, p.month)} ${p.year}'
                  '${p.isPartial ? ' (partial)' : ''}',
              _currency.format(p.income),
              _currency.format(p.outflow),
              _currency.format(p.net),
            ],
        ],
      ),
      chart: points.isEmpty
          ? _empty(context, 'No cash flow in this period.')
          : SizedBox(height: 220, child: _bars(context)),
    );
  }

  String _summary() {
    if (points.isEmpty) return 'Monthly cash flow: no data in this period.';
    final last = points.last;
    return 'Monthly cash flow over ${points.length} months. '
        'Latest month ${_monthLabel(last.year, last.month)}: income '
        '${_currency.format(last.income)}, total outflow '
        '${_currency.format(last.outflow)}.';
  }

  Widget _bars(BuildContext context) {
    final maxY = points.fold<double>(
        0, (m, p) => [m, p.income, p.outflow].reduce((a, b) => a > b ? a : b));

    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY * 1.15,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, rodIndex) {
              final p = points[group.x];
              final isIncome = rodIndex == 0;
              return BarTooltipItem(
                '${_monthLabel(p.year, p.month)} ${p.year}\n'
                '${isIncome ? 'Income' : 'Total Outflow'}: '
                '${_currency.format(isIncome ? p.income : p.outflow)}',
                const TextStyle(color: AppTheme.paper, fontSize: 11),
              );
            },
          ),
          touchCallback: (event, response) {
            if (!event.isInterestedForInteractions || response?.spot == null) {
              return;
            }
            final group = response!.spot!.touchedBarGroupIndex;
            final rod = response.spot!.touchedRodDataIndex;
            onMonthTap?.call(points[group], rod == 0);
          },
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: ChartTheme.grid, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (value, meta) => Text(
                _compact.format(value),
                style: ChartTheme.axisLabel(context),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                // Thin the labels so they never collide on a narrow screen.
                final step = (points.length / 6).ceil();
                if (points.length > 6 && i % step != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_monthLabel(points[i].year, points[i].month),
                      style: ChartTheme.axisLabel(context)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 2,
              barRods: [
                _rod(points[i].income, ChartTheme.series1, points[i].isPartial),
                _rod(points[i].outflow, ChartTheme.series2, points[i].isPartial),
              ],
            ),
        ],
      ),
    );
  }

  BarChartRodData _rod(double value, Color color, bool partial) =>
      BarChartRodData(
        toY: value,
        width: ChartTheme.barWidth,
        // Square shoulders, 4px rounded data end.
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        color: partial ? color.withValues(alpha: ChartTheme.partialOpacity) : color,
      );
}

// --- Chart 2: Spending by Primary Label -------------------------------------

/// Sorted horizontal bars. One series, so every bar takes slot 1 — colouring
/// bars darker-where-bigger would re-encode length as hue and spend the
/// identity channel on information the bar already shows.
///
/// The two review buckets are the exception: they are not categories, so they
/// take a different slot AND say so in words.
class LabelSpendChart extends StatelessWidget {
  const LabelSpendChart({
    super.key,
    required this.slices,
    required this.includeFamily,
    this.onLabelTap,
    this.onReviewTap,
  });

  final List<LabelSpend> slices;
  final bool includeFamily;
  final void Function(LabelSpend slice)? onLabelTap;
  final VoidCallback? onReviewTap;

  @override
  Widget build(BuildContext context) {
    final shown = LabelSpend.topWithOther(slices);
    final total = shown.fold<double>(0, (s, e) => s + e.amount);
    final maxAmount = shown.fold<double>(0, (m, e) => e.amount > m ? e.amount : m);

    return ChartFrame(
      title: 'Spending by label',
      note: includeFamily
          ? 'Personal Spend and Family Support.'
          : 'Personal Spend only. Family Support is excluded.',
      summary: _summary(shown, total),
      table: ChartTable(
        headers: const ['Label', 'Amount', 'Share'],
        rows: [
          for (final s in shown)
            [
              s.name,
              _currency.format(s.amount),
              total == 0 ? '—' : '${(s.amount / total * 100).toStringAsFixed(1)}%',
            ],
        ],
      ),
      chart: shown.isEmpty
          ? _empty(context, 'No spending in this period.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final slice in shown)
                  _Row(
                    slice: slice,
                    fraction: maxAmount == 0 ? 0 : slice.amount / maxAmount,
                    onTap: slice.bucket == SpendBucket.label
                        ? () => onLabelTap?.call(slice)
                        : (slice.bucket == SpendBucket.other
                            ? null
                            : onReviewTap),
                  ),
              ],
            ),
    );
  }

  String _summary(List<LabelSpend> shown, double total) {
    if (shown.isEmpty) return 'Spending by label: no spending in this period.';
    final top = shown.first;
    return 'Spending by label, ${_currency.format(total)} total across '
        '${shown.length} groups. Largest is ${top.name} at '
        '${_currency.format(top.amount)}.';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.slice, required this.fraction, this.onTap});

  final LabelSpend slice;
  final double fraction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isReview = slice.bucket == SpendBucket.unlabeled ||
        slice.bucket == SpendBucket.needsPrimary;
    final color = isReview ? ChartTheme.series3 : ChartTheme.series1;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    slice.name,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Direct value label: the readability channel the palette
                // requires, and it saves a tap to learn the number.
                Text(_currency.format(slice.amount),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  flex: (fraction * 1000).round().clamp(1, 1000),
                  child: Container(height: 10, color: color),
                ),
                Expanded(
                  flex: (1000 - (fraction * 1000).round()).clamp(0, 999),
                  child: const SizedBox(height: 10),
                ),
              ],
            ),
            if (isReview)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  slice.bucket == SpendBucket.unlabeled
                      ? 'Not a category — these expenses carry no label. Tap to review.'
                      : 'Not a category — no primary label chosen. Tap to review.',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: ChartTheme.mutedInk),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- Chart 3: Daily Cumulative Personal Spend -------------------------------

/// Two lines aligned by day number. No budget or target line is drawn — the
/// app has no budget concept, and inventing one would imply a commitment the
/// owner never made.
class DailyCumulativeChart extends StatelessWidget {
  const DailyCumulativeChart({
    super.key,
    required this.points,
    this.onDayTap,
  });

  final List<DailyCumulativePoint> points;
  final void Function(int day)? onDayTap;

  @override
  Widget build(BuildContext context) {
    final current = points.where((p) => p.current != null).toList();

    return ChartFrame(
      title: 'Daily cumulative personal spend',
      note: 'This month against last, aligned by day. The current line stops '
          'at today.',
      summary: _summary(current),
      legend: const ChartLegend(entries: [
        (label: 'This month', color: ChartTheme.series1),
        (label: 'Last month', color: ChartTheme.series2),
      ]),
      table: ChartTable(
        headers: const ['Day', 'This month', 'Last month'],
        rows: [
          for (final p in points)
            [
              '${p.day}',
              p.current == null ? '—' : _currency.format(p.current!),
              _currency.format(p.previous),
            ],
        ],
      ),
      chart: points.length < 2
          ? _empty(context, 'Not enough of the month has passed to compare.')
          : SizedBox(height: 200, child: _lines(context, current)),
    );
  }

  String _summary(List<DailyCumulativePoint> current) {
    if (current.isEmpty) {
      return 'Daily cumulative personal spend: nothing spent yet this month.';
    }
    final today = current.last;
    final samePoint = points.firstWhere((p) => p.day == today.day,
        orElse: () => today);
    return 'Cumulative personal spend by day ${today.day}: '
        '${_currency.format(today.current ?? 0)} this month against '
        '${_currency.format(samePoint.previous)} at the same point last month.';
  }

  Widget _lines(BuildContext context, List<DailyCumulativePoint> current) {
    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      'Day ${s.x.toInt()}\n${_currency.format(s.y)}',
                      const TextStyle(color: AppTheme.paper, fontSize: 11),
                    ))
                .toList(),
          ),
          touchCallback: (event, response) {
            if (!event.isInterestedForInteractions) return;
            final spot = response?.lineBarSpots?.firstOrNull;
            if (spot != null) onDayTap?.call(spot.x.toInt());
          },
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: ChartTheme.grid, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (value, meta) => Text(_compact.format(value),
                  style: ChartTheme.axisLabel(context)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 5,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${value.toInt()}',
                    style: ChartTheme.axisLabel(context)),
              ),
            ),
          ),
        ),
        lineBarsData: [
          _line(
            [for (final p in points) FlSpot(p.day.toDouble(), p.previous)],
            ChartTheme.series2,
          ),
          _line(
            [for (final p in current) FlSpot(p.day.toDouble(), p.current!)],
            ChartTheme.series1,
          ),
        ],
      ),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) => LineChartBarData(
        spots: spots,
        color: color,
        barWidth: ChartTheme.lineWidth,
        isCurved: false,
        // A single point would otherwise render as an invisible zero-length
        // line; show the dot instead.
        dotData: FlDotData(show: spots.length == 1),
      );
}

// --- Chart 4: Net Worth History ---------------------------------------------

/// One series, so no legend box — the title names it. Periods whose snapshot
/// cannot be trusted are omitted from the line and called out in words, never
/// interpolated across.
class NetWorthChart extends StatelessWidget {
  const NetWorthChart({
    super.key,
    required this.points,
    required this.current,
  });

  final List<NetWorthPoint> points;
  final double current;

  @override
  Widget build(BuildContext context) {
    final usable = points.where((p) => p.available && p.value != null).toList();
    final unavailable = points.length - usable.length;

    return ChartFrame(
      title: 'Net worth history',
      note: unavailable > 0
          ? '$unavailable earlier month${unavailable == 1 ? '' : 's'} cannot be '
              'charted: those snapshots were recorded before the as-of fix and '
              'may include later transactions. They are omitted, not estimated.'
          : 'Month-end values, plus today’s live figure.',
      summary: 'Net worth history across ${usable.length} recorded months. '
          'Current net worth ${_currency.format(current)}.',
      table: ChartTable(
        headers: const ['Month', 'Net worth'],
        rows: [
          for (final p in points)
            [
              '${_monthLabel(p.year, p.month)} ${p.year}',
              p.available && p.value != null
                  ? _currency.format(p.value!)
                  : 'unavailable',
            ],
          ['Today (live)', _currency.format(current)],
        ],
      ),
      chart: usable.isEmpty
          ? _empty(context,
              'No month-end snapshots yet. The first arrives after this month closes.')
          : SizedBox(height: 200, child: _line(context, usable)),
    );
  }

  Widget _line(BuildContext context, List<NetWorthPoint> usable) {
    final spots = [
      for (var i = 0; i < usable.length; i++)
        FlSpot(i.toDouble(), usable[i].value!),
      FlSpot(usable.length.toDouble(), current),
    ];

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => touched.map((s) {
              final i = s.x.toInt();
              final label = i >= usable.length
                  ? 'Today (live)'
                  : '${_monthLabel(usable[i].year, usable[i].month)} '
                      '${usable[i].year}';
              return LineTooltipItem(
                '$label\n${_currency.format(s.y)}',
                const TextStyle(color: AppTheme.paper, fontSize: 11),
              );
            }).toList(),
          ),
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: ChartTheme.grid, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (value, meta) => Text(_compact.format(value),
                  style: ChartTheme.axisLabel(context)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i > usable.length) return const SizedBox.shrink();
                if (i == usable.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child:
                        Text('now', style: ChartTheme.axisLabel(context)),
                  );
                }
                final step = (usable.length / 5).ceil();
                if (usable.length > 5 && i % step != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_monthLabel(usable[i].year, usable[i].month),
                      style: ChartTheme.axisLabel(context)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: ChartTheme.series1,
            barWidth: ChartTheme.lineWidth,
            isCurved: false,
            // Only the live point is marked, so "today" is unmistakable
            // without a second colour.
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, _) =>
                  spot.x == usable.length.toDouble() || spots.length == 1,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: ChartTheme.markerRadius,
                color: ChartTheme.series1,
                strokeWidth: 2,
                strokeColor: ChartTheme.surface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
