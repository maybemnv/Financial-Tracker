import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/transaction.dart';

void main() {
  group('Transaction.effectiveDate', () {
    test('falls back to createdAt when transactedAt is null', () {
      final createdAt = DateTime(2026, 7, 1, 9, 30);
      final tx = Transaction(
        amount: 250,
        type: 'debit',
        createdAt: createdAt,
      );

      expect(
        tx.effectiveDate,
        createdAt,
        reason:
            'effectiveDate must use createdAt when transactedAt is null so legacy/server-dated rows still group correctly.',
      );
    });

    test('uses transactedAt when it is set', () {
      final createdAt = DateTime(2026, 7, 1, 9, 30);
      final transactedAt = DateTime(2026, 6, 30, 21, 45);
      final tx = Transaction(
        amount: 250,
        type: 'debit',
        createdAt: createdAt,
        transactedAt: transactedAt,
      );

      expect(
        tx.effectiveDate,
        transactedAt,
        reason:
            'effectiveDate must prefer transactedAt because it is the actual money-move date.',
      );
    });
  });
}
