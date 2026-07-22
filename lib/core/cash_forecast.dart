import 'obligations.dart';

/// Measured inputs for the forecast. Every field is observed, never estimated —
/// the estimating happens in one place, [CashForecast.project].
class ForecastInputs {
  const ForecastInputs({
    required this.liquidBalance,
    required this.investmentBalance,
    required this.earmarkedTotal,
    required this.personalSpendPerDay,
    required this.lookbackDays,
  });

  /// Cash and bank only. Investment accounts hold value, not spendable money.
  final double liquidBalance;
  final double investmentBalance;

  /// Goal allocations. Context only — this money has not left the accounts, so
  /// the forecast never subtracts it.
  final double earmarkedTotal;

  /// Average daily Personal Spend over [lookbackDays]. Family Support is
  /// excluded: it is real money leaving, but driven by obligation rather than
  /// habit, so averaging it into a discretionary burn rate overstates it.
  final double personalSpendPerDay;
  final int lookbackDays;

  static const int supportedVersion = 1;

  factory ForecastInputs.fromRpc(Map<String, dynamic> json) {
    final version = (json['version'] as num?)?.toInt();
    if (version != supportedVersion) {
      throw FormatException(
        'Forecast inputs version $version is not supported by this build '
        '(expected $supportedVersion).',
      );
    }
    double n(String k) => (json[k] as num?)?.toDouble() ?? 0;
    return ForecastInputs(
      liquidBalance: n('liquid_balance'),
      investmentBalance: n('investment_balance'),
      earmarkedTotal: n('earmarked_total'),
      personalSpendPerDay: n('personal_spend_per_day'),
      lookbackDays: (json['lookback_days'] as num?)?.toInt() ?? 90,
    );
  }
}

/// A dated line in the projection.
class ForecastEvent {
  const ForecastEvent({
    required this.date,
    required this.name,
    required this.amount,
  });

  final DateTime date;
  final String name;

  /// Signed: negative is money out.
  final double amount;
}

/// A deterministic 30-day cash projection (TODO 9.2).
///
/// Arithmetic only, no model, no ML. Every number below can be recomputed by
/// hand from [inputs] and [events], which is exactly the property the roadmap
/// asks for — the assumptions are returned alongside the result so the owner
/// can check them rather than trust them.
class CashForecast {
  const CashForecast({
    required this.horizon,
    required this.openingLiquid,
    required this.projectedLiquid,
    required this.expectedInflow,
    required this.expectedOutflow,
    required this.estimatedDiscretionarySpend,
    required this.events,
    required this.obligationsBeforeNextInflow,
    required this.safeToSpend,
    required this.nextInflowDate,
    required this.assumptions,
    required this.earmarkedTotal,
    required this.investmentBalance,
  });

  final Duration horizon;
  final double openingLiquid;

  /// Opening balance, plus known inflows, minus known outflows and the
  /// projected discretionary spend.
  final double projectedLiquid;

  final double expectedInflow;
  final double expectedOutflow;
  final double estimatedDiscretionarySpend;
  final List<ForecastEvent> events;

  /// Obligations landing before the next expected inflow — the ones that must
  /// be covered by money already in hand.
  final double obligationsBeforeNextInflow;

  /// Liquid balance minus those obligations, floored at zero. An estimate, and
  /// labelled as one everywhere it is shown.
  final double safeToSpend;

  final DateTime? nextInflowDate;

  /// Human-readable statement of everything assumed, shown with the result.
  final List<String> assumptions;

  /// Shown beside the balance for context, never subtracted from it.
  final double earmarkedTotal;
  final double investmentBalance;

  static CashForecast project({
    required ForecastInputs inputs,
    required List<Obligation> obligations,
    required DateTime now,
    Duration horizon = const Duration(days: 30),
  }) {
    final today = DateTime(now.year, now.month, now.day);

    final events = <ForecastEvent>[];
    for (final o in obligations) {
      for (final date in o.occurrencesWithin(horizon, now: now)) {
        events.add(ForecastEvent(
          date: date,
          name: o.name,
          amount: o.signedAmount,
        ));
      }
    }
    events.sort((a, b) => a.date.compareTo(b.date));

    final inflow = events
        .where((e) => e.amount > 0)
        .fold<double>(0, (s, e) => s + e.amount);
    final outflow = events
        .where((e) => e.amount < 0)
        .fold<double>(0, (s, e) => s + -e.amount);

    final discretionary = inputs.personalSpendPerDay * horizon.inDays;

    final nextInflow = events.where((e) => e.amount > 0).firstOrNull?.date;
    final beforeInflow = events
        .where((e) =>
            e.amount < 0 &&
            (nextInflow == null || !e.date.isAfter(nextInflow)))
        .fold<double>(0, (s, e) => s + -e.amount);

    final safe = inputs.liquidBalance - beforeInflow;

    return CashForecast(
      horizon: horizon,
      openingLiquid: inputs.liquidBalance,
      projectedLiquid:
          inputs.liquidBalance + inflow - outflow - discretionary,
      expectedInflow: inflow,
      expectedOutflow: outflow,
      estimatedDiscretionarySpend: discretionary,
      events: events,
      obligationsBeforeNextInflow: beforeInflow,
      safeToSpend: safe < 0 ? 0 : safe,
      nextInflowDate: nextInflow,
      earmarkedTotal: inputs.earmarkedTotal,
      investmentBalance: inputs.investmentBalance,
      assumptions: [
        'Starting from ${_money(inputs.liquidBalance)} in cash and bank '
            'accounts as of ${_date(today)}.',
        'Investment balances are excluded — they hold value, not spendable '
            'cash.',
        'Discretionary spend projected at ${_money(inputs.personalSpendPerDay)}'
            '/day, the Personal Spend average over the last '
            '${inputs.lookbackDays} days, for ${horizon.inDays} days.',
        'Family Support is not in that daily rate; it is counted only where a '
            'recurring obligation records it.',
        if (inputs.earmarkedTotal > 0)
          '${_money(inputs.earmarkedTotal)} is earmarked for goals. That money '
              'is still in your accounts and has not been subtracted.',
        'Paused and already-confirmed obligations are excluded.',
        'This is arithmetic on the figures above, not a prediction.',
      ],
    );
  }

  static String _money(double v) => '₹${v.round()}';
  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
