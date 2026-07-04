import 'package:finance_tracker/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('Transaction flow direction', () {
    test('infers inflow for legacy credit rows without explicit direction', () {
      final tx = Transaction(amount: 100, type: 'credit');

      expect(tx.isInflow, isTrue,
          reason:
              'Legacy credit rows must still behave like inflows before every stored row has direction populated.');
      expect(tx.isOutflow, isFalse);
    });

    test('uses explicit direction for transfer and investment legs', () {
      final transferIn = Transaction(
        amount: 300,
        type: 'transfer',
        direction: 'inflow',
      );
      final investmentOut = Transaction(
        amount: 300,
        type: 'investment',
        direction: 'outflow',
      );

      expect(transferIn.isInflow, isTrue,
          reason:
              'Transfer legs need explicit flow direction to balance accounts correctly.');
      expect(investmentOut.isOutflow, isTrue,
          reason:
              'Investment source legs must reduce the source account balance.');
    });
  });

  group('Transaction serialization', () {
    test('round-trips direction, tags, and transactedAt', () {
      final original = Transaction(
        accountId: 'cash',
        amount: 499.99,
        type: 'investment',
        direction: 'outflow',
        merchant: 'Index Fund',
        tags: const ['sip', 'long_term'],
        source: 'manual',
        transferGroupId: '123e4567-e89b-12d3-a456-426614174000',
        transactedAt: DateTime(2026, 7, 5, 20, 15),
      );

      final json = original.toJson();
      final roundTrip = Transaction.fromJson({
        ...json,
        'id': 'tx-1',
        'created_at': '2026-07-05T20:16:00.000Z',
      });

      expect(roundTrip.direction, 'outflow');
      expect(roundTrip.type, 'investment');
      expect(roundTrip.tags, ['sip', 'long_term']);
      expect(roundTrip.transferGroupId, original.transferGroupId);
      expect(roundTrip.transactedAt, original.transactedAt);
    });
  });
}
