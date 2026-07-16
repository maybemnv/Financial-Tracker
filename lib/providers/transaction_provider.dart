import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/dedup.dart';
import '../core/supabase.dart';
import '../models/transaction.dart';
import '../models/transaction_label.dart';

/// Loads, mutates, and live-syncs transactions.
///
/// Hardening: [add] dedups SMS-sourced rows by `raw_sms_hash`; [delete] is a
/// SOFT delete (`is_deleted = true`, never `DELETE`); [update] appends an
/// `{old, new, edited_at}` entry to the immutable `edit_history` JSONB.
class TransactionNotifier extends StateNotifier<AsyncValue<List<Transaction>>> {
  TransactionNotifier() : super(const AsyncValue.loading());

  static final Random _random = Random.secure();

  RealtimeChannel? _channel;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await SupabaseService()
          .client
          .from('transactions')
          .select('*, transaction_labels(label:labels(id, name, color))')
          .eq('is_deleted', false)
          .order('created_at', ascending: false);
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
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          table: 'transaction_labels',
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

    final payload = tx.copyWith(
      rawSmsHash: hash ?? tx.rawSmsHash,
      direction: tx.direction ?? _defaultDirectionForType(tx.type),
    );
    final response = await SupabaseService()
        .client
        .from('transactions')
        .insert(payload.toJson())
        .select();
    final inserted = (response as List?)?.firstOrNull;
    if (inserted != null && payload.labels.isNotEmpty) {
      await _replaceLabels(
        inserted['id'] as String,
        payload.labels,
      );
    }
    await load();
    return true;
  }

  /// Updates a transaction, appending the prior + new values and a timestamp to
  /// `edit_history` so nothing is ever silently overwritten.
  Future<void> update(Transaction tx) async {
    if (tx.id == null) return;
    final client = SupabaseService().client;

    final existing = await client
        .from('transactions')
        .select(
            'amount, type, direction, merchant, vpa, bank, note, account_id, edit_history')
        .eq('id', tx.id!)
        .maybeSingle();
    if (existing != null) {
      final history = (existing['edit_history'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      history.add({
        'old': existing..remove('edit_history'),
        'new': tx.toJson(),
        'edited_at': DateTime.now().toIso8601String(),
      });
      await client.from('transactions').update({
        ...tx.toJson(),
        'edit_history': history,
      }).eq('id', tx.id!);
    } else {
      await client.from('transactions').update(tx.toJson()).eq('id', tx.id!);
    }
    await _replaceLabels(tx.id!, tx.labels);
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

  /// Records a double-entry transfer with explicit outflow and inflow legs.
  Future<void> addTransfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    String? note,
    DateTime? transactedAt,
    List<TransactionLabel> labels = const [],
  }) async {
    await _addAccountMove(
      type: 'transfer',
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amount: amount,
      note: note,
      transactedAt: transactedAt,
      labels: labels,
    );
  }

  /// Records an investment move out of a cash/bank account into an investment account.
  Future<void> addInvestment({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    String? note,
    DateTime? transactedAt,
    List<TransactionLabel> labels = const [],
  }) async {
    await _addAccountMove(
      type: 'investment',
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amount: amount,
      note: note,
      transactedAt: transactedAt,
      labels: labels,
    );
  }

  Future<void> _addAccountMove({
    required String type,
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    String? note,
    DateTime? transactedAt,
    List<TransactionLabel> labels = const [],
  }) async {
    final groupId = _generateGroupId();
    final legs = [
      Transaction(
        accountId: fromAccountId,
        amount: amount,
        type: type,
        direction: 'outflow',
        note: note,
        transferGroupId: groupId,
        source: 'manual',
        transactedAt: transactedAt,
        labels: labels,
      ),
      Transaction(
        accountId: toAccountId,
        amount: amount,
        type: type,
        direction: 'inflow',
        note: note,
        transferGroupId: groupId,
        source: 'manual',
        transactedAt: transactedAt,
        labels: labels,
      ),
    ];
    final inserted = await SupabaseService().client.from('transactions').insert(
          legs.map((t) => t.toJson()).toList(),
        ).select('id');
    if (labels.isNotEmpty) {
      for (final row in inserted as List) {
        await _replaceLabels(row['id'] as String, labels);
      }
    }
    await load();
  }

  Future<void> _replaceLabels(
    String transactionId,
    List<TransactionLabel> labels,
  ) async {
    final client = SupabaseService().client;
    await client
        .from('transaction_labels')
        .delete()
        .eq('transaction_id', transactionId);
    if (labels.isEmpty) return;
    final rows = labels
        .where((label) => label.id != null)
        .map(
          (label) => {
            'transaction_id': transactionId,
            'label_id': label.id,
          },
        )
        .toList();
    if (rows.isNotEmpty) {
      await client.from('transaction_labels').insert(rows);
    }
  }

  String _defaultDirectionForType(String type) {
    switch (type) {
      case 'credit':
        return 'inflow';
      case 'debit':
      case 'transfer':
      case 'investment':
      default:
        return 'outflow';
    }
  }

  String _generateGroupId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        buffer.write('-');
      }
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}

final transactionProvider =
    StateNotifierProvider<TransactionNotifier, AsyncValue<List<Transaction>>>(
        (ref) {
  final notifier = TransactionNotifier();
  notifier.load();
  notifier.subscribe();
  ref.onDispose(() => notifier.unsubscribe());
  return notifier;
});
