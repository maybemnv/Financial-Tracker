import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/dedup.dart';
import '../core/supabase.dart';
import '../models/transaction.dart';

/// Loads, mutates, and live-syncs transactions.
///
/// Hardening: [add] dedups SMS-sourced rows by `raw_sms_hash`; [delete] is a
/// SOFT delete (`is_deleted = true`, never `DELETE`); [update] appends an
/// `{old, new, edited_at}` entry to the immutable `edit_history` JSONB. A
/// transfer inserts two linked rows sharing a `transfer_group_id`.
class TransactionNotifier extends StateNotifier<AsyncValue<List<Transaction>>> {
  RealtimeChannel? _channel;

  TransactionNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await SupabaseService().client
          .from('transactions')
          .select()
          .eq('is_deleted', false)
          .order('created_at', ascending: false)
          .limit(200);
      final transactions = (data as List)
          .map((json) => Transaction.fromJson(json as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(transactions);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void subscribe() {
    _channel = SupabaseService()
        .client
        .channel('transactions')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          table: 'transactions',
          callback: (_) => load(),
        )
        .subscribe();
  }

  void unsubscribe() {
    _channel?.unsubscribe();
  }

  /// Inserts a transaction. SMS-sourced rows are deduped by `raw_sms_hash`:
  /// returns false (no insert) if the hash already exists.
  Future<bool> add(Transaction tx) async {
    final hash = Dedup.hashSms(tx.rawSms);
    if (tx.source == 'sms' && hash != null) {
      final dup = await SupabaseService()
          .client
          .from('transactions')
          .select('id')
          .eq('raw_sms_hash', hash)
          .maybeSingle();
      if (dup != null) return false;
    }

    final payload = (hash != null) ? tx.copyWith(rawSmsHash: hash) : tx;
    final response = await SupabaseService()
        .client
        .from('transactions')
        .insert(payload.toJson())
        .select();
    final inserted = (response as List?)?.firstOrNull;
    if (inserted != null) {
      state = state.whenData(
          (list) => [Transaction.fromJson(inserted as Map<String, dynamic>), ...list]);
    } else {
      await load();
    }
    return true;
  }

  /// Updates a transaction, appending the prior + new values and a timestamp to
  /// `edit_history` so nothing is ever silently overwritten.
  Future<void> update(Transaction tx) async {
    if (tx.id == null) return;
    final client = SupabaseService().client;

    final existing = await client
        .from('transactions')
        .select('amount, type, category, merchant, vpa, tags, note, account_id, edit_history')
        .eq('id', tx.id!)
        .maybeSingle();
    if (existing != null) {
      final history = (existing['edit_history'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      history.add({
        'old': existing
          ..remove('edit_history'),
        'new': tx.toJson(),
        'edited_at': DateTime.now().toIso8601String(),
      });
      await client
          .from('transactions')
          .update({
            ...tx.toJson(),
            'edit_history': history,
          })
          .eq('id', tx.id!);
    } else {
      await client.from('transactions').update(tx.toJson()).eq('id', tx.id!);
    }
    await load();
  }

  /// SOFT delete — sets `is_deleted` + `deleted_at`. Nothing is ever hard
  /// deleted. Uses an ISO timestamp, not the `'now()'` string literal.
  Future<void> delete(String id) async {
    await SupabaseService().client.from('transactions').update({
      'is_deleted': true,
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    await load();
  }

  /// Records a double-entry transfer: one debit from [fromAccountId], one
  /// credit to [toAccountId], both sharing a generated `transfer_group_id`.
  /// Net worth is unchanged — money only moves between accounts.
  Future<void> addTransfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    String? note,
  }) async {
    final groupId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final legs = [
      Transaction(
        accountId: fromAccountId,
        amount: amount,
        type: 'transfer',
        note: note,
        transferGroupId: groupId,
        source: 'manual',
      ),
      Transaction(
        accountId: toAccountId,
        amount: amount,
        type: 'transfer',
        note: note,
        transferGroupId: groupId,
        source: 'manual',
      ),
    ];
    await SupabaseService().client.from('transactions').insert(
          legs.map((t) => t.toJson()).toList(),
        );
    await load();
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}

final transactionProvider =
    StateNotifierProvider<TransactionNotifier, AsyncValue<List<Transaction>>>((ref) {
  final notifier = TransactionNotifier();
  notifier.load();
  notifier.subscribe();
  ref.onDispose(() => notifier.unsubscribe());
  return notifier;
});
