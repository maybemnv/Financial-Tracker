import '../models/transaction.dart';
import '../models/transaction_label.dart';
import 'finance_metrics.dart';

/// How a label is actually used across the ledger. Drives the impact summaries
/// the management screen shows before rename / archive / merge / delete, so an
/// action is never confirmed blind (TODO 5.11).
class LabelUsage {
  const LabelUsage({
    this.attachedCount = 0,
    this.primaryCount = 0,
    this.attributedAmount = 0,
  });

  /// Transactions carrying this label, contextual or primary.
  final int attachedCount;

  /// Expenses whose full amount attributes to this label.
  final int primaryCount;

  /// Sum of those expenses. What would move buckets if the label changed.
  final double attributedAmount;

  /// A label with no references at all can be safely deleted; `delete_label`
  /// enforces the same rule and raises otherwise.
  bool get isUnreferenced => attachedCount == 0;

  /// Contextual-only attachments — present for search and filtering, but
  /// contributing no money to this label's reported total.
  int get contextualCount => attachedCount - primaryCount;
}

/// Usage counts per label id, derived from the loaded ledger.
///
/// Deliberately computed from transactions already in memory rather than a new
/// aggregate RPC: Phase 7 replaces the full-ledger provider, and adding a
/// server round-trip here would be thrown away with it.
Map<String, LabelUsage> computeLabelUsage(Iterable<Transaction> transactions) {
  final attached = <String, int>{};
  final primary = <String, int>{};
  final amount = <String, double>{};

  for (final t in transactions) {
    if (t.isDeleted) continue;

    for (final label in t.labels) {
      final id = label.id;
      if (id == null) continue;
      attached[id] = (attached[id] ?? 0) + 1;
    }

    // Only expenses attribute money, and only through their primary label.
    if (!FinanceMetrics.isExpense(t)) continue;
    final primaryId = t.primaryLabel?.id;
    if (primaryId == null) continue;
    primary[primaryId] = (primary[primaryId] ?? 0) + 1;
    amount[primaryId] = (amount[primaryId] ?? 0) + t.amount;
  }

  return {
    for (final id in {...attached.keys, ...primary.keys})
      id: LabelUsage(
        attachedCount: attached[id] ?? 0,
        primaryCount: primary[id] ?? 0,
        attributedAmount: amount[id] ?? 0,
      ),
  };
}

/// Expenses the owner still has to classify (TODO 5.5 review queue).
class LabelReviewQueue {
  const LabelReviewQueue({
    required this.needsPrimary,
    required this.unlabeled,
  });

  /// Multi-label expenses with no primary chosen — the amount cannot be
  /// attributed until one is picked.
  final List<Transaction> needsPrimary;

  /// Expenses with no labels at all. Valid, and reported as `Unlabeled`, but
  /// worth classifying.
  final List<Transaction> unlabeled;

  int get total => needsPrimary.length + unlabeled.length;
  bool get isEmpty => total == 0;

  static LabelReviewQueue from(Iterable<Transaction> transactions) {
    final needsPrimary = <Transaction>[];
    final unlabeled = <Transaction>[];
    for (final t in transactions) {
      if (t.isDeleted) continue;
      switch (FinanceMetrics.primaryStatus(t)) {
        case PrimaryLabelStatus.needsPrimaryLabel:
          needsPrimary.add(t);
        case PrimaryLabelStatus.unlabeled:
          unlabeled.add(t);
        case PrimaryLabelStatus.resolved:
        case PrimaryLabelStatus.notRequired:
          break;
      }
    }
    return LabelReviewQueue(needsPrimary: needsPrimary, unlabeled: unlabeled);
  }
}

/// Labels a merge may target: active, not the source itself.
/// Mirrors `merge_labels`, which rejects anything else.
List<TransactionLabel> mergeTargetsFor(
  TransactionLabel source,
  Iterable<TransactionLabel> all,
) =>
    all
        .where((l) => l.isAssignable && l.id != null && l.id != source.id)
        .toList(growable: false);
