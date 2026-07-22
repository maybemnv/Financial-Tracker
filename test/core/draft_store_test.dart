import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_tracker/core/draft_store.dart';

/// Phase 11.5 — draft persistence rejects malformed, expired, and wrong-owner
/// records, and never keeps a bad one around.
void main() {
  late DraftStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await DraftStore.open();
  });

  test('a saved draft round-trips for the same owner', () {
    store.save('txn', 'owner-a', {'amount': '250', 'merchant': 'biryani'});
    final loaded = store.load('txn', 'owner-a');
    expect(loaded, isNotNull);
    expect(loaded!['amount'], '250');
    expect(loaded['merchant'], 'biryani');
  });

  test('a draft from another owner is never restored', () {
    store.save('txn', 'owner-a', {'amount': '250'});
    expect(store.load('txn', 'owner-b'), isNull,
        reason: 'A different account must never see the previous owner\'s '
            'half-typed transaction.');
    // And the rejection clears it, so it cannot resurface.
    expect(store.load('txn', 'owner-a'), isNull);
  });

  test('an expired draft is dropped', () async {
    final prefs = await SharedPreferences.getInstance();
    // Hand-write an envelope older than the 24h TTL.
    final stale = DateTime.now().subtract(const Duration(hours: 25));
    prefs.setString(
      'draft.txn',
      '{"v":1,"owner":"owner-a","saved_at":"${stale.toIso8601String()}",'
          '"data":{"amount":"250"}}',
    );
    expect(store.load('txn', 'owner-a'), isNull);
  });

  test('a draft just inside the TTL survives', () async {
    final prefs = await SharedPreferences.getInstance();
    final fresh = DateTime.now().subtract(const Duration(hours: 23));
    prefs.setString(
      'draft.txn',
      '{"v":1,"owner":"owner-a","saved_at":"${fresh.toIso8601String()}",'
          '"data":{"amount":"250"}}',
    );
    expect(store.load('txn', 'owner-a'), isNotNull);
  });

  test('an incompatible schema version is dropped, not coerced', () async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(
      'draft.txn',
      '{"v":99,"owner":"owner-a","saved_at":"${DateTime.now().toIso8601String()}",'
          '"data":{"amount":"250"}}',
    );
    expect(store.load('txn', 'owner-a'), isNull,
        reason: 'A future schema must be discarded rather than read with '
            'today\'s field assumptions.');
  });

  test('malformed JSON is discarded', () async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('draft.txn', 'not json at all');
    expect(store.load('txn', 'owner-a'), isNull);
    expect(prefs.getString('draft.txn'), isNull, reason: 'and cleared');
  });

  test('sign-out clears every draft', () {
    store.save('txn', 'owner-a', {'amount': '1'});
    store.save('tab', 'owner-a', {'index': 2});
    store.clearAll();
    expect(store.load('txn', 'owner-a'), isNull);
    expect(store.load('tab', 'owner-a'), isNull);
  });

  group('the draft carries only what was typed', () {
    test('the transaction DTO exposes no token or fetched money data', () {
      const draft = TransactionDraft(
        amount: '250',
        merchant: 'biryani',
        labelIds: ['food'],
        primaryLabelId: 'food',
      );
      final json = draft.toJson();
      // Whitelist: exactly the entered fields, nothing that could leak a
      // session or balance.
      expect(json.keys.toSet(), {
        'amount',
        'type',
        'account_id',
        'merchant',
        'note',
        'label_ids',
        'primary_label_id',
      });
    });

    test('round-trips through json', () {
      const draft = TransactionDraft(
        amount: '99',
        type: 'debit',
        accountId: 'cash',
        labelIds: ['a', 'b'],
        primaryLabelId: 'a',
      );
      final back = TransactionDraft.fromJson(draft.toJson());
      expect(back.amount, '99');
      expect(back.accountId, 'cash');
      expect(back.labelIds, ['a', 'b']);
      expect(back.primaryLabelId, 'a');
    });

    test('emptiness is judged on entered content', () {
      expect(const TransactionDraft().isEmpty, isTrue);
      expect(const TransactionDraft(type: 'debit').isEmpty, isTrue,
          reason: 'A default type alone is not a draft worth restoring.');
      expect(const TransactionDraft(amount: '5').isEmpty, isFalse);
    });
  });
}
