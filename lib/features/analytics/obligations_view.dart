import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/cash_forecast.dart';
import '../../core/obligations.dart';
import '../../core/theme.dart';
import '../../providers/forecast_provider.dart';
import '../../widgets/newsprint_primitives.dart';

final _currency =
    NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
final _day = DateFormat('d MMM');

/// Upcoming obligations, ordered by due date (Phase 9.1).
class ObligationsList extends ConsumerWidget {
  const ObligationsList({super.key, this.limit});

  /// Compact mode for Briefing.
  final int? limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(obligationsProvider);
    final shown = limit == null ? all : all.take(limit!).toList();

    if (shown.isEmpty) {
      return Text(
        'No recurring income or expenses recorded yet.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final o in shown) _ObligationRow(obligation: o),
        if (limit != null && all.length > limit!)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('+${all.length - limit!} more in Analytics',
                style: Theme.of(context).textTheme.labelSmall),
          ),
      ],
    );
  }
}

class _ObligationRow extends StatelessWidget {
  const _ObligationRow({required this.obligation});

  final Obligation obligation;

  @override
  Widget build(BuildContext context) {
    final o = obligation;
    final (statusText, statusColor) = switch (o.status) {
      ObligationStatus.overdue => ('Overdue', AppTheme.redAccent),
      ObligationStatus.today => ('Due today', AppTheme.accentGold),
      ObligationStatus.confirmed => ('Confirmed', AppTheme.primaryGreen),
      ObligationStatus.paused => ('Paused', AppTheme.inkSoft),
      ObligationStatus.upcoming => (
          o.daysRemaining == null ? 'No date' : 'in ${o.daysRemaining}d',
          AppTheme.inkSoft,
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.name, style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  [
                    if (o.dueDate != null) _day.format(o.dueDate!),
                    // Status is words, not colour alone.
                    statusText,
                  ].join(' · '),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: statusColor),
                ),
              ],
            ),
          ),
          Text(
            '${o.isExpense ? '−' : '+'}${_currency.format(o.amount)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: o.isExpense ? AppTheme.ink : AppTheme.primaryGreen,
                ),
          ),
        ],
      ),
    );
  }
}

/// The 30-day projection, presented as an estimate with its assumptions
/// visible (Phase 9.2).
class ForecastCard extends ConsumerWidget {
  const ForecastCard({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cashForecastProvider);

    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Forecast unavailable: $e',
          style: Theme.of(context).textTheme.bodySmall),
      data: (f) => _Body(forecast: f, compact: compact),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.forecast, required this.compact});

  final CashForecast forecast;
  final bool compact;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _showAssumptions = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.forecast;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            NewsprintMetricStrip(
              label: 'Safe to spend',
              value: _currency.format(f.safeToSpend),
            ),
            NewsprintMetricStrip(
              label: 'In ${f.horizon.inDays} days',
              value: _currency.format(f.projectedLiquid),
              valueColor: f.projectedLiquid < 0 ? AppTheme.redAccent : null,
            ),
            if (!widget.compact) ...[
              NewsprintMetricStrip(
                  label: 'Expected in',
                  value: _currency.format(f.expectedInflow)),
              NewsprintMetricStrip(
                  label: 'Committed out',
                  value: _currency.format(f.expectedOutflow)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          f.nextInflowDate == null
              ? 'No expected inflow in the next ${f.horizon.inDays} days, so '
                  '"safe to spend" is your balance less what is already committed.'
              : 'Estimate: your balance less the '
                  '${_currency.format(f.obligationsBeforeNextInflow)} due before '
                  'the next expected inflow on ${_day.format(f.nextInflowDate!)}.',
          style: theme.textTheme.bodySmall,
        ),
        if (f.earmarkedTotal > 0)
          Text(
            '${_currency.format(f.earmarkedTotal)} of this is earmarked for '
            'goals — still in your accounts, not deducted here.',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppTheme.inkSoft),
          ),
        if (!widget.compact) ...[
          TextButton(
            onPressed: () =>
                setState(() => _showAssumptions = !_showAssumptions),
            child: Text(_showAssumptions ? 'HIDE WORKING' : 'SHOW WORKING'),
          ),
          if (_showAssumptions)
            // Shown in full so the number can be checked, not just trusted.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final a in f.assumptions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $a', style: theme.textTheme.bodySmall),
                  ),
                if (f.events.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Dated items in the window',
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  for (final e in f.events)
                    Text(
                      '${_day.format(e.date)} · ${e.name} · '
                      '${e.amount < 0 ? '−' : '+'}'
                      '${_currency.format(e.amount.abs())}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ],
            ),
        ],
      ],
    );
  }
}
