import '../models/transaction.dart';

/// Derived attribution state of an expense's primary label (PRD §4 / TODO 5.3).
enum PrimaryLabelStatus {
  /// Not an expense (credit / transfer / investment) — no primary required.
  notRequired,

  /// Exactly one primary label resolved.
  resolved,

  /// An expense with no labels at all.
  unlabeled,

  /// A multi-label expense with no primary chosen yet.
  needsPrimaryLabel,
}

/// Canonical financial metrics — the single source of truth for Briefing,
/// Analytics, exports, and Agent Desk (PRD §4). Implemented once here so every
/// surface reconciles to the same numbers.
///
/// Reconciliation invariant, guaranteed by construction:
///   totalOutflow == personalSpend + familySupport
class FinanceMetrics {
  const FinanceMetrics({
    required this.income,
    required this.totalOutflow,
    required this.familySupport,
  });

  /// External inflows classified as earned/received: `credit` rows (incl.
  /// PayPal payouts/deposits). Excludes transfer and investment inflow legs.
  final double income;

  /// All external `debit` outflows — Personal Spend plus Family Support.
  /// Excludes transfer and investment legs.
  final double totalOutflow;

  /// Debit outflows whose primary label is flagged `exclude_from_personal_spend`
  /// (the `FAMILY` label). Counted in Total Outflow, never in Personal Spend.
  final double familySupport;

  /// Debit outflows whose primary label is not excluded (incl. unlabeled and
  /// `needsPrimaryLabel`, which count as Personal Spend until classified).
  double get personalSpend => totalOutflow - familySupport;

  /// `Income − Total Outflow`. The default "savings" figure everywhere.
  double get netCashSurplus => income - totalOutflow;

  /// `Income − Personal Spend`. Context only — NOT retained money, because
  /// Family Support has also left the accounts. UI copy must not call it kept.
  double get personalSavingsAfterOwnSpend => income - personalSpend;

  /// `Net Cash Surplus / Income × 100` (0 when income is 0).
  double get savingsRate => income == 0 ? 0 : (netCashSurplus / income) * 100;

  static FinanceMetrics compute(Iterable<Transaction> transactions) {
    var income = 0.0;
    var totalOutflow = 0.0;
    var familySupport = 0.0;

    for (final t in transactions) {
      if (t.isDeleted) continue;
      if (isIncome(t)) {
        income += t.amount;
      } else if (isExpense(t)) {
        totalOutflow += t.amount;
        if (isFamilySupport(t)) familySupport += t.amount;
      }
      // transfers and investments are excluded from all three metrics.
    }

    return FinanceMetrics(
      income: income,
      totalOutflow: totalOutflow,
      familySupport: familySupport,
    );
  }

  // --- Shared classification (also used by DashboardAnalytics) --------------

  /// External earned/received inflow. PayPal payouts/deposits count as income.
  static bool isIncome(Transaction t) {
    if (t.isTransfer || t.isInvestment) return false;
    if (t.isInflow && t.isPayPalPayoutOrDeposit) return true;
    return t.type == 'credit' || t.isInflow;
  }

  /// External debit outflow (Personal Spend or Family Support).
  static bool isExpense(Transaction t) {
    if (t.isTransfer || t.isInvestment) return false;
    if (isIncome(t)) return false;
    return t.type == 'debit' || t.isOutflow;
  }

  static bool isInvestmentOutflow(Transaction t) =>
      t.isInvestment && t.isOutflow;

  /// A debit whose primary label is flagged excluded (the `FAMILY` label).
  /// Unlabeled / needs-primary expenses are Personal Spend until classified.
  static bool isFamilySupport(Transaction t) {
    if (!isExpense(t)) return false;
    final primary = t.primaryLabel;
    return primary != null && primary.excludeFromPersonalSpend;
  }

  static PrimaryLabelStatus primaryStatus(Transaction t) {
    if (!isExpense(t)) return PrimaryLabelStatus.notRequired;
    if (t.labels.isEmpty) return PrimaryLabelStatus.unlabeled;
    if (t.primaryLabel != null) return PrimaryLabelStatus.resolved;
    return PrimaryLabelStatus.needsPrimaryLabel;
  }
}
