import 'package:finance_tracker/models/transaction.dart';
import 'package:finance_tracker/models/transaction_label.dart';
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
    test('round-trips direction, labels, and transactedAt', () {
      final original = Transaction(
        accountId: 'cash',
        amount: 499.99,
        type: 'investment',
        direction: 'outflow',
        merchant: 'Index Fund',
        labels: const [
          TransactionLabel(id: 'label-1', name: 'SIP', color: '#1D76DB'),
          TransactionLabel(id: 'label-2', name: 'Long term', color: '#0E8A16'),
        ],
        source: 'manual',
        transferGroupId: '123e4567-e89b-12d3-a456-426614174000',
        transactedAt: DateTime(2026, 7, 5, 20, 15),
      );

      final json = original.toJson();
      final roundTrip = Transaction.fromJson({
        ...json,
        'id': 'tx-1',
        'created_at': '2026-07-05T20:16:00.000Z',
        'transaction_labels': [
          {
            'label': {'id': 'label-1', 'name': 'SIP', 'color': '#1D76DB'},
          },
          {
            'label': {
              'id': 'label-2',
              'name': 'Long term',
              'color': '#0E8A16',
            },
          },
        ],
      });

      expect(roundTrip.direction, 'outflow');
      expect(roundTrip.type, 'investment');
      expect(roundTrip.labels.map((label) => label.name), ['SIP', 'Long term']);
      expect(roundTrip.transferGroupId, original.transferGroupId);
      expect(roundTrip.transactedAt, original.transactedAt);
    });
  });

  group('Transaction.fromJson label shapes', () {
    // `get_transaction_page` (migration 00017) emits a flat `labels` array.
    // A direct PostgREST select embeds `transaction_labels(label:labels(*))`.
    // Reading only the embedded shape silently emptied every row's labels.
    test('parses the flat labels array the paged ledger RPC returns', () {
      final tx = Transaction.fromJson({
        'amount': 420,
        'type': 'debit',
        'labels': [
          {
            'id': 'label-1',
            'name': 'GROCERIES',
            'color': '#0E8A16',
            'status': 'active',
            'exclude_from_personal_spend': false,
          },
          {
            'id': 'label-2',
            'name': 'FAMILY',
            'color': '#1D76DB',
            'status': 'active',
            'exclude_from_personal_spend': true,
          },
        ],
      });

      expect(tx.labels.map((l) => l.name), ['GROCERIES', 'FAMILY']);
      expect(tx.labels.last.excludeFromPersonalSpend, isTrue);
    });

    test('still parses the embedded PostgREST join shape', () {
      final tx = Transaction.fromJson({
        'amount': 420,
        'type': 'debit',
        'transaction_labels': [
          {
            'label': {'id': 'label-1', 'name': 'SIP', 'color': '#1D76DB'},
          },
        ],
      });

      expect(tx.labels.map((l) => l.name), ['SIP']);
    });

    test('yields no labels when the row carries none', () {
      final tx = Transaction.fromJson({
        'amount': 420,
        'type': 'debit',
        'labels': <dynamic>[],
      });

      expect(tx.labels, isEmpty);
    });

    test('skips malformed entries instead of throwing', () {
      final tx = Transaction.fromJson({
        'amount': 420,
        'type': 'debit',
        'labels': [
          {'id': 'orphan'}, // no name/color — an incomplete row
          {'id': 'label-1', 'name': 'RENT', 'color': '#B60205'},
        ],
      });

      expect(tx.labels.map((l) => l.name), ['RENT']);
    });
  });
}
