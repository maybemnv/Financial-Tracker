/// Typed DTOs for the Phase 7.4 aggregate RPCs.
///
/// The RPCs return a versioned envelope; these parse it once at the boundary so
/// widgets never index into dynamic maps. An unrecognised version throws rather
/// than yielding a screen full of zeros — a wrong number is worse than an error.
library;

int _requireVersion(Map<String, dynamic> json, int expected, String what) {
  final version = (json['version'] as num?)?.toInt();
  if (version != expected) {
    throw FormatException(
      '$what version $version is not supported by this build '
      '(expected $expected). Update the app.',
    );
  }
  return version!;
}

double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

/// Canonical PRD §4 metrics for one month, computed server-side.
///
/// Mirrors [FinanceMetrics] exactly. `personalSpend` is returned by the server
/// as `totalOutflow - familySupport` rather than summed independently, so the
/// reconciliation invariant cannot drift between the two implementations.
class BriefingSummary {
  const BriefingSummary({
    required this.month,
    required this.year,
    required this.income,
    required this.totalOutflow,
    required this.familySupport,
    required this.personalSpend,
    required this.netCashSurplus,
    required this.investments,
    required this.savingsRate,
    required this.needsPrimaryCount,
    required this.unlabeledCount,
  });

  final int month;
  final int year;
  final double income;
  final double totalOutflow;
  final double familySupport;
  final double personalSpend;
  final double netCashSurplus;
  final double investments;
  final double savingsRate;

  /// Standing review backlog, not month-scoped.
  final int needsPrimaryCount;
  final int unlabeledCount;

  static const int supportedVersion = 1;

  factory BriefingSummary.fromRpc(Map<String, dynamic> json) {
    _requireVersion(json, supportedVersion, 'Briefing summary');
    return BriefingSummary(
      month: (json['month'] as num).toInt(),
      year: (json['year'] as num).toInt(),
      income: _num(json['income']),
      totalOutflow: _num(json['total_outflow']),
      familySupport: _num(json['family_support']),
      personalSpend: _num(json['personal_spend']),
      netCashSurplus: _num(json['net_cash_surplus']),
      investments: _num(json['investments']),
      savingsRate: _num(json['savings_rate']),
      needsPrimaryCount: (json['needs_primary_count'] as num?)?.toInt() ?? 0,
      unlabeledCount: (json['unlabeled_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// The PRD §4 reconciliation invariant. Asserted at the boundary so a server
  /// regression surfaces here rather than as a quietly wrong dashboard.
  bool get reconciles =>
      (totalOutflow - (personalSpend + familySupport)).abs() < 0.01;
}

/// One account with its derived balance.
class AccountBalance {
  const AccountBalance({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
  });

  final String id;
  final String name;
  final String type;
  final double balance;

  factory AccountBalance.fromJson(Map<String, dynamic> json) => AccountBalance(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String? ?? 'bank',
        balance: _num(json['balance']),
      );

  static List<AccountBalance> listFromRpc(Map<String, dynamic> json) {
    _requireVersion(json, 1, 'Account balances');
    return (json['accounts'] as List? ?? const [])
        .map((a) => AccountBalance.fromJson(Map<String, dynamic>.from(a as Map)))
        .toList(growable: false);
  }
}

/// Whole-ledger usage for one label.
///
/// Server-derived: once the ledger is paged, counting loaded rows would report
/// per-page numbers and understate what a rename/merge/archive actually
/// affects.
class LabelUsageStat {
  const LabelUsageStat({
    required this.labelId,
    required this.attachedCount,
    required this.primaryCount,
    required this.attributedAmount,
  });

  final String labelId;
  final int attachedCount;
  final int primaryCount;
  final double attributedAmount;

  bool get isUnreferenced => attachedCount == 0;
  int get contextualCount => attachedCount - primaryCount;

  factory LabelUsageStat.fromJson(Map<String, dynamic> json) => LabelUsageStat(
        labelId: json['label_id'] as String,
        attachedCount: (json['attached_count'] as num?)?.toInt() ?? 0,
        primaryCount: (json['primary_count'] as num?)?.toInt() ?? 0,
        attributedAmount: _num(json['attributed_amount']),
      );

  static Map<String, LabelUsageStat> mapFromRpc(Map<String, dynamic> json) {
    _requireVersion(json, 1, 'Label usage');
    final stats = (json['labels'] as List? ?? const [])
        .map((l) => LabelUsageStat.fromJson(Map<String, dynamic>.from(l as Map)));
    return {for (final s in stats) s.labelId: s};
  }
}
