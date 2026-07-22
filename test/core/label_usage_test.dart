import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/core/label_usage.dart';
import 'package:finance_tracker/models/transaction.dart';
import 'package:finance_tracker/models/transaction_label.dart';

/// Phase 5.11 / 5.5 — usage counts behind the impact summaries, and the review
/// queue that resolves unattributed spend.
void main() {
  const food = TransactionLabel(id: 'food', name: 'Food', color: '#111111');
  const travel = TransactionLabel(id: 'travel', name: 'Travel', color: '#222222');
  const archived = TransactionLabel(
    id: 'old',
    name: 'Old',
    color: '#333333',
    status: 'archived',
  );

  Transaction expense({
    required double amount,
    List<TransactionLabel> labels = const [],
    String? primaryLabelId,
    bool isDeleted = false,
  }) =>
      Transaction(
        amount: amount,
        type: 'debit',
        accountId: 'a1',
        labels: labels,
        primaryLabelId: primaryLabelId,
        isDeleted: isDeleted,
      );

  group('usage counts', () {
    test('separates primary attribution from contextual attachment', () {
      final usage = computeLabelUsage([
        // Food is primary; Travel is only context on the same row.
        expense(amount: 300, labels: [food, travel], primaryLabelId: 'food'),
        expense(amount: 200, labels: [food], primaryLabelId: 'food'),
      ]);

      expect(usage['food']!.attachedCount, 2);
      expect(usage['food']!.primaryCount, 2);
      expect(usage['food']!.attributedAmount, 500);

      expect(usage['travel']!.attachedCount, 1);
      expect(usage['travel']!.primaryCount, 0,
          reason: 'A contextual label must never absorb the amount — that was '
              'the even-split defect (D3).');
      expect(usage['travel']!.attributedAmount, 0);
      expect(usage['travel']!.contextualCount, 1);
    });

    test('a single label is primary by fallback', () {
      final usage = computeLabelUsage([
        expense(amount: 100, labels: [food]),
      ]);
      expect(usage['food']!.primaryCount, 1,
          reason: 'Transaction.primaryLabel falls back to the sole label, so '
              'single-label legacy rows still attribute.');
      expect(usage['food']!.attributedAmount, 100);
    });

    test('a multi-label expense with no primary attributes nothing', () {
      final usage = computeLabelUsage([
        expense(amount: 900, labels: [food, travel]),
      ]);
      expect(usage['food']!.attachedCount, 1);
      expect(usage['food']!.primaryCount, 0);
      expect(usage['food']!.attributedAmount, 0);
      expect(usage['travel']!.attributedAmount, 0);
    });

    test('income never attributes to a label', () {
      final usage = computeLabelUsage([
        Transaction(
          amount: 5000,
          type: 'credit',
          accountId: 'a1',
          labels: const [food],
          primaryLabelId: 'food',
        ),
      ]);
      expect(usage['food']!.attachedCount, 1);
      expect(usage['food']!.primaryCount, 0,
          reason: 'Only expenses attribute spend.');
    });

    test('deleted rows are ignored', () {
      final usage = computeLabelUsage([
        expense(amount: 100, labels: [food], isDeleted: true),
      ]);
      expect(usage['food'], isNull);
    });

    test('an unreferenced label is the only deletable one', () {
      final usage = computeLabelUsage([expense(amount: 100, labels: [food])]);
      expect(usage['food']!.isUnreferenced, isFalse);
      expect(const LabelUsage().isUnreferenced, isTrue);
    });
  });

  group('review queue', () {
    test('splits needs-primary from unlabeled and ignores resolved rows', () {
      final needsPrimary =
          expense(amount: 400, labels: [food, travel]); // ambiguous
      final unlabeled = expense(amount: 250); // no labels
      final resolved =
          expense(amount: 100, labels: [food, travel], primaryLabelId: 'food');
      final single = expense(amount: 50, labels: [food]); // fallback resolves

      final queue = LabelReviewQueue.from(
          [needsPrimary, unlabeled, resolved, single]);

      expect(queue.needsPrimary, [needsPrimary]);
      expect(queue.unlabeled, [unlabeled]);
      expect(queue.total, 2);
    });

    test('income is never queued', () {
      final queue = LabelReviewQueue.from([
        Transaction(amount: 900, type: 'credit', accountId: 'a1'),
      ]);
      expect(queue.isEmpty, isTrue,
          reason: 'Only expenses require a primary label.');
    });

    test('a clean ledger reports empty', () {
      final queue = LabelReviewQueue.from([
        expense(amount: 100, labels: [food], primaryLabelId: 'food'),
      ]);
      expect(queue.isEmpty, isTrue);
    });
  });

  group('merge targets', () {
    test('exclude the source and anything unassignable', () {
      final targets = mergeTargetsFor(food, [food, travel, archived]);
      expect(targets.map((l) => l.id), ['travel'],
          reason: 'merge_labels rejects an archived or merged target, and a '
              'label cannot merge into itself.');
    });

    test('empty when nothing else is assignable', () {
      expect(mergeTargetsFor(food, [food, archived]), isEmpty);
    });
  });
}
