import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/core/ledger_query.dart';
import 'package:finance_tracker/models/transaction.dart';
import 'package:finance_tracker/models/transaction_label.dart';

/// Phase 7.1/7.2 — the typed query, the keyset cursor, and the versioned page
/// envelope. The SQL side is exercised by `supabase/tests/ledger_paging.sql`.
void main() {
  const food = TransactionLabel(id: 'food', name: 'Food', color: '#111111');

  Transaction tx({
    String id = 't1',
    String type = 'debit',
    String? accountId = 'cash',
    String? merchant,
    String? note,
    List<TransactionLabel> labels = const [],
    DateTime? transactedAt,
    bool isDeleted = false,
  }) =>
      Transaction(
        id: id,
        amount: 100,
        type: type,
        accountId: accountId,
        merchant: merchant,
        note: note,
        labels: labels,
        transactedAt: transactedAt ?? DateTime(2026, 7, 10),
        isDeleted: isDeleted,
      );

  group('query equality drives page resets', () {
    test('same filters compare equal', () {
      expect(const LedgerQuery(accountId: 'a'),
          const LedgerQuery(accountId: 'a'));
      expect(const LedgerQuery(accountId: 'a').hashCode,
          const LedgerQuery(accountId: 'a').hashCode);
    });

    test('a changed filter is a different query', () {
      expect(const LedgerQuery(accountId: 'a'),
          isNot(const LedgerQuery(accountId: 'b')));
      expect(const LedgerQuery(),
          isNot(const LedgerQuery(unresolved: UnresolvedFilter.needsPrimary)));
    });

    test('copyWith can clear a filter, not just replace it', () {
      const q = LedgerQuery(accountId: 'a', search: 'coffee');
      expect(q.copyWith(clearAccount: true).accountId, isNull);
      expect(q.copyWith(clearAccount: true).search, 'coffee',
          reason: 'Clearing one filter must not disturb the others.');
    });
  });

  group('wire parameters', () {
    test('a null cursor requests the first page', () {
      final params = const LedgerQuery().toParams(limit: 50);
      expect(params['p_cursor_at'], isNull);
      expect(params['p_cursor_id'], isNull);
      expect(params['p_limit'], 50);
    });

    test('blank search is sent as null, not an empty string', () {
      final params = const LedgerQuery(search: '   ').toParams(limit: 50);
      expect(params['p_search'], isNull,
          reason: 'An empty term must not become a LIKE %% scan.');
    });

    test('unresolved filters map to their wire values', () {
      expect(const LedgerQuery().toParams(limit: 1)['p_unresolved'], isNull);
      expect(
        const LedgerQuery(unresolved: UnresolvedFilter.needsPrimary)
            .toParams(limit: 1)['p_unresolved'],
        'needs_primary',
      );
      expect(
        const LedgerQuery(unresolved: UnresolvedFilter.unlabeled)
            .toParams(limit: 1)['p_unresolved'],
        'unlabeled',
      );
    });

    test('the cursor is sent as an ISO timestamp plus id', () {
      final cursor = LedgerCursor(
          effectiveAt: DateTime.utc(2026, 7, 10, 12), id: 'abc');
      final params = const LedgerQuery().toParams(limit: 50, cursor: cursor);
      expect(params['p_cursor_at'], '2026-07-10T12:00:00.000Z');
      expect(params['p_cursor_id'], 'abc');
    });
  });

  group('local match — deciding replace vs remove after an edit', () {
    test('a deleted row never matches', () {
      expect(const LedgerQuery().matches(tx(isDeleted: true)), isFalse);
    });

    test('account and type filters exclude', () {
      expect(const LedgerQuery(accountId: 'bank').matches(tx()), isFalse);
      expect(const LedgerQuery(accountId: 'cash').matches(tx()), isTrue);
      expect(const LedgerQuery(type: 'credit').matches(tx()), isFalse);
    });

    test('label filter checks attachments', () {
      expect(const LedgerQuery(labelId: 'food').matches(tx()), isFalse);
      expect(
          const LedgerQuery(labelId: 'food').matches(tx(labels: [food])), isTrue);
    });

    test('search spans merchant, note, and vpa, case-insensitively', () {
      expect(const LedgerQuery(search: 'CAFE').matches(tx(merchant: 'Corner Cafe')),
          isTrue);
      expect(const LedgerQuery(search: 'rent').matches(tx(note: 'Monthly Rent')),
          isTrue);
      expect(const LedgerQuery(search: 'zzz').matches(tx(merchant: 'Cafe')),
          isFalse);
    });

    test('date range excludes rows outside it', () {
      final q = LedgerQuery(from: DateTime(2026, 7, 1), to: DateTime(2026, 7, 31));
      expect(q.matches(tx(transactedAt: DateTime(2026, 7, 10))), isTrue);
      expect(q.matches(tx(transactedAt: DateTime(2026, 6, 10))), isFalse);
    });
  });

  group('page envelope', () {
    Map<String, dynamic> envelope({
      int version = 1,
      List<Map<String, dynamic>> rows = const [],
      bool hasMore = false,
      Map<String, dynamic>? cursor,
    }) =>
        {
          'version': version,
          'rows': rows,
          'has_more': hasMore,
          'next_cursor': cursor,
        };

    test('parses rows, cursor, and has_more', () {
      final page = LedgerPage.fromRpc(envelope(
        rows: [
          {
            'id': 'a',
            'amount': 250,
            'type': 'debit',
            'account_id': 'cash',
            'transacted_at': '2026-07-10T00:00:00.000Z',
          }
        ],
        hasMore: true,
        cursor: {'at': '2026-07-10T00:00:00.000Z', 'id': 'a'},
      ));

      expect(page.rows.single.id, 'a');
      expect(page.hasMore, isTrue);
      expect(page.nextCursor!.id, 'a');
    });

    test('an empty page yields no cursor', () {
      final page = LedgerPage.fromRpc(envelope());
      expect(page.rows, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });

    test('an unknown version is rejected, not silently misread', () {
      expect(
        () => LedgerPage.fromRpc(envelope(version: 2)),
        throwsA(isA<FormatException>()),
        reason: 'A newer server shape must fail loudly rather than produce a '
            'ledger full of nulls.',
      );
    });
  });

  group('cursor', () {
    test('equal timestamps still differentiate by id', () {
      final at = DateTime.utc(2026, 7, 10);
      expect(LedgerCursor(effectiveAt: at, id: 'a'),
          isNot(LedgerCursor(effectiveAt: at, id: 'b')),
          reason: 'The id tiebreak is what stops equal-timestamp rows from '
              'repeating or being skipped across pages.');
    });

    test('a malformed cursor is treated as absent', () {
      expect(LedgerCursor.fromJson(null), isNull);
      expect(LedgerCursor.fromJson({'at': null, 'id': 'a'}), isNull);
      expect(LedgerCursor.fromJson({'at': '2026-07-10T00:00:00Z'}), isNull);
    });
  });
}
