/// Typed analytics contracts (Phase 8.2). Currency, month boundaries, missing
/// periods, and percentage precision are defined here once so no chart invents
/// its own convention.
library;

/// Selectable window. 12M is the default.
enum AnalyticsPeriod {
  oneMonth('1M', 1),
  threeMonths('3M', 3),
  sixMonths('6M', 6),
  twelveMonths('12M', 12),
  yearToDate('YTD', 0),
  all('All', 120);

  const AnalyticsPeriod(this.label, this._months);

  final String label;
  final int _months;

  static const AnalyticsPeriod defaultPeriod = AnalyticsPeriod.twelveMonths;

  /// Month count to request. YTD is resolved against [now] rather than stored,
  /// so the window is correct whenever it is asked for.
  int monthsAsOf(DateTime now) =>
      this == AnalyticsPeriod.yearToDate ? now.month : _months;
}

/// What the analytics bundle was asked for.
class AnalyticsQuery {
  const AnalyticsQuery({
    this.period = AnalyticsPeriod.defaultPeriod,
    this.includeFamilySupport = false,
  });

  final AnalyticsPeriod period;

  /// Chart 2 defaults to Personal Spend only. The toggle adds Family Support
  /// and changes nothing else — it never alters attribution.
  final bool includeFamilySupport;

  AnalyticsQuery copyWith({
    AnalyticsPeriod? period,
    bool? includeFamilySupport,
  }) =>
      AnalyticsQuery(
        period: period ?? this.period,
        includeFamilySupport:
            includeFamilySupport ?? this.includeFamilySupport,
      );

  @override
  bool operator ==(Object other) =>
      other is AnalyticsQuery &&
      other.period == period &&
      other.includeFamilySupport == includeFamilySupport;

  @override
  int get hashCode => Object.hash(period, includeFamilySupport);
}

double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

/// Chart 1 point: one month of income vs total outflow.
class CashFlowPoint {
  const CashFlowPoint({
    required this.year,
    required this.month,
    required this.income,
    required this.outflow,
    required this.familySupport,
    required this.isPartial,
  });

  final int year;
  final int month;
  final double income;
  final double outflow;
  final double familySupport;

  /// The current month, which is still accumulating. Rendered distinctly so a
  /// short bar is never mistaken for a real drop.
  final bool isPartial;

  double get personalSpend => outflow - familySupport;
  double get net => income - outflow;

  factory CashFlowPoint.fromJson(Map<String, dynamic> j) => CashFlowPoint(
        year: (j['year'] as num).toInt(),
        month: (j['month'] as num).toInt(),
        income: _num(j['income']),
        outflow: _num(j['outflow']),
        familySupport: _num(j['family_support']),
        isPartial: j['is_partial'] as bool? ?? false,
      );
}

/// Which bucket a spending slice belongs to. `unlabeled` and `needsPrimary`
/// are shown distinctly and link to the review queue — they are not categories.
enum SpendBucket { label, unlabeled, needsPrimary, other }

/// Chart 2 slice: spend attributed to one primary label.
class LabelSpend {
  const LabelSpend({
    required this.name,
    required this.amount,
    this.labelId,
    this.excluded = false,
    this.bucket = SpendBucket.label,
  });

  final String? labelId;
  final String name;
  final double amount;

  /// Family Support (`exclude_from_personal_spend`).
  final bool excluded;
  final SpendBucket bucket;

  factory LabelSpend.fromJson(Map<String, dynamic> j) => LabelSpend(
        labelId: j['label_id'] as String?,
        name: j['name'] as String? ?? 'Unlabeled',
        amount: _num(j['amount']),
        excluded: j['excluded'] as bool? ?? false,
        bucket: switch (j['bucket'] as String?) {
          'unlabeled' => SpendBucket.unlabeled,
          'needs_primary' => SpendBucket.needsPrimary,
          _ => SpendBucket.label,
        },
      );

  /// Top [keep] slices with the remainder folded into a single `Other`.
  ///
  /// The fold is what keeps the chart inside the validated palette's series
  /// cap, and `Other` is a real sum — top-N plus Other always equals the
  /// ungrouped total (asserted in tests).
  static List<LabelSpend> topWithOther(List<LabelSpend> all, {int keep = 7}) {
    if (all.length <= keep) return all;
    final sorted = [...all]..sort((a, b) => b.amount.compareTo(a.amount));
    final head = sorted.take(keep).toList();
    final tail = sorted.skip(keep);
    final rest = tail.fold<double>(0, (sum, s) => sum + s.amount);
    if (rest <= 0) return head;
    return [
      ...head,
      LabelSpend(name: 'Other', amount: rest, bucket: SpendBucket.other),
    ];
  }
}

/// Chart 3 point: cumulative personal spend on day N, this month vs last.
class DailyCumulativePoint {
  const DailyCumulativePoint({
    required this.day,
    required this.current,
    required this.previous,
  });

  final int day;

  /// Null past today — the current month stops at today rather than flattening
  /// to a line that implies zero spend for the rest of the month.
  final double? current;
  final double previous;

  factory DailyCumulativePoint.fromJson(Map<String, dynamic> j, int today) {
    final day = (j['day'] as num).toInt();
    return DailyCumulativePoint(
      day: day,
      current: day <= today ? _num(j['current']) : null,
      previous: _num(j['previous']),
    );
  }
}

/// Chart 4 point: net worth at a month end.
class NetWorthPoint {
  const NetWorthPoint({
    required this.year,
    required this.month,
    required this.value,
    required this.available,
    this.isCurrent = false,
  });

  final int year;
  final int month;

  /// Null when the period's value cannot be trusted. Never interpolated.
  final double? value;

  /// False for snapshots still on the pre-00018 unbounded basis, which could
  /// include transactions from after the month they claim to describe.
  final bool available;
  final bool isCurrent;

  factory NetWorthPoint.fromJson(Map<String, dynamic> j) => NetWorthPoint(
        year: (j['year'] as num).toInt(),
        month: (j['month'] as num).toInt(),
        value: j['value'] == null ? null : _num(j['value']),
        available: j['available'] as bool? ?? false,
      );
}

class MerchantTotal {
  const MerchantTotal({
    required this.merchant,
    required this.amount,
    required this.count,
  });

  final String merchant;
  final double amount;
  final int count;

  factory MerchantTotal.fromJson(Map<String, dynamic> j) => MerchantTotal(
        merchant: j['merchant'] as String? ?? 'Unknown',
        amount: _num(j['amount']),
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

/// Everything the Analytics tab renders, from one call.
class AnalyticsBundle {
  const AnalyticsBundle({
    required this.cashFlow,
    required this.byLabel,
    required this.dailySpend,
    required this.netWorth,
    required this.netWorthCurrent,
    required this.topMerchants,
    required this.includeFamilySupport,
  });

  final List<CashFlowPoint> cashFlow;
  final List<LabelSpend> byLabel;
  final List<DailyCumulativePoint> dailySpend;
  final List<NetWorthPoint> netWorth;
  final double netWorthCurrent;
  final List<MerchantTotal> topMerchants;
  final bool includeFamilySupport;

  static const int supportedVersion = 1;

  factory AnalyticsBundle.fromRpc(Map<String, dynamic> json, {DateTime? now}) {
    final version = (json['version'] as num?)?.toInt();
    if (version != supportedVersion) {
      throw FormatException(
        'Analytics version $version is not supported by this build '
        '(expected $supportedVersion). Update the app.',
      );
    }
    final today = (now ?? DateTime.now()).day;
    List<Map<String, dynamic>> rows(String key) =>
        (json[key] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    return AnalyticsBundle(
      cashFlow: rows('cash_flow').map(CashFlowPoint.fromJson).toList(),
      byLabel: rows('by_label').map(LabelSpend.fromJson).toList(),
      dailySpend: rows('daily_spend')
          .map((j) => DailyCumulativePoint.fromJson(j, today))
          .toList(),
      netWorth: rows('net_worth').map(NetWorthPoint.fromJson).toList(),
      netWorthCurrent: _num(json['net_worth_current']),
      topMerchants: rows('top_merchants').map(MerchantTotal.fromJson).toList(),
      includeFamilySupport: json['include_family'] as bool? ?? false,
    );
  }

  /// Total spend across every bucket — the figure top-N + Other must equal.
  double get totalLabelledSpend =>
      byLabel.fold<double>(0, (sum, s) => sum + s.amount);
}
