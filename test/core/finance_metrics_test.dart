import 'package:finance_tracker/core/finance_metrics.dart';
import 'package:finance_tracker/models/transaction.dart';
import 'package:finance_tracker/models/transaction_label.dart';
import 'package:flutter_test/flutter_test.dart';

const _food = TransactionLabel(id: 'food', name: 'Food', color: '#1D76DB');
const _family = TransactionLabel(
  id: 'family',
  name: 'FAMILY',
  color: '#B60205',
  excludeFromPersonalSpend: true,
);

Transaction _debit(double amount,
        {List<TransactionLabel> labels = const [], String? primaryLabelId}) =>
    Transaction(
      amount: amount,
      type: 'debit',
      direction: 'outflow',
      accountId: 'cash',
      labels: labels,
      primaryLabelId: primaryLabelId,
      createdAt: DateTime(2026, 7, 3),
    );

Transaction _credit(double amount, {String? merchant, String? note}) =>
    Transaction(
      amount: amount,
      type: 'credit',
      direction: 'inflow',
      accountId: 'bank',
      merchant: merchant,
      note: note,
      createdAt: DateTime(2026, 7, 3),
    );

void main() {
  group('FinanceMetrics (PRD §4)', () {
    test('income counts credits incl. PayPal; excludes transfers/investments',
        () {
      final m = FinanceMetrics.compute([
        _credit(5000),
        _credit(3000, merchant: 'PayPal', note: 'PayPal payout X'),
        Transaction(
            amount: 400,
            type: 'transfer',
            direction: 'inflow',
            accountId: 'a',
            createdAt: DateTime(2026, 7, 4)),
        Transaction(
            amount: 900,
            type: 'investment',
            direction: 'inflow',
            accountId: 'a',
            createdAt: DateTime(2026, 7, 4)),
      ]);
      expect(m.income, 8000);
      expect(m.totalOutflow, 0);
    });

    test('FAMILY debit is in Total Outflow and Family Support, never Personal',
        () {
      final m = FinanceMetrics.compute([
        _debit(1200, labels: const [_food]),
        _debit(500, labels: const [_family]),
      ]);
      expect(m.totalOutflow, 1700);
      expect(m.familySupport, 500);
      expect(m.personalSpend, 1200);
    });

    test('invariant: Total Outflow == Personal Spend + Family Support', () {
      final m = FinanceMetrics.compute([
        _debit(1200, labels: const [_food]),
        _debit(500, labels: const [_family]),
        _debit(300), // unlabeled -> personal spend
        _debit(700, labels: const [_food, _family]), // no primary -> personal
        _credit(9000),
      ]);
      expect(m.totalOutflow, m.personalSpend + m.familySupport);
      // unlabeled + multi-no-primary are Personal Spend until classified.
      expect(m.familySupport, 500);
      expect(m.personalSpend, 1200 + 300 + 700);
    });

    test('a multi-label debit whose primary is FAMILY is Family Support', () {
      final m = FinanceMetrics.compute([
        _debit(700, labels: const [_food, _family], primaryLabelId: 'family'),
      ]);
      expect(m.familySupport, 700);
      expect(m.personalSpend, 0);
    });

    test('net cash surplus, savings rate, and after-own-spend framing', () {
      final m = FinanceMetrics.compute([
        _credit(10000),
        _debit(2000, labels: const [_food]),
        _debit(1000, labels: const [_family]),
      ]);
      expect(m.netCashSurplus, 7000); // income - total outflow
      expect(m.savingsRate, closeTo(70, 0.001));
      // After-own-spend is higher (8000) but is NOT retained money.
      expect(m.personalSavingsAfterOwnSpend, 8000);
    });

    test('savings rate is 0 when income is 0', () {
      final m = FinanceMetrics.compute([_debit(500)]);
      expect(m.savingsRate, 0);
    });

    test('primary status classification', () {
      expect(FinanceMetrics.primaryStatus(_credit(1)),
          PrimaryLabelStatus.notRequired);
      expect(FinanceMetrics.primaryStatus(_debit(1)),
          PrimaryLabelStatus.unlabeled);
      expect(FinanceMetrics.primaryStatus(_debit(1, labels: const [_food])),
          PrimaryLabelStatus.resolved);
      expect(
          FinanceMetrics.primaryStatus(
              _debit(1, labels: const [_food, _family])),
          PrimaryLabelStatus.needsPrimaryLabel);
    });
  });
}
