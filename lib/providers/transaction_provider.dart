import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase.dart';
import '../models/transaction.dart';

class TransactionNotifier extends StateNotifier<AsyncValue<List<Transaction>>> {
  StreamSubscription? _subscription;

  TransactionNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await SupabaseService().client
          .from('transactions')
          .select()
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
    _subscription = SupabaseService()
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
    _subscription?.cancel();
  }

  Future<void> add(Transaction tx) async {
    final response = await SupabaseService().client.from('transactions').insert(tx.toJson()).select();
    final inserted = (response as List?)?.firstOrNull;
    if (inserted != null) {
      state = state.whenData((list) => [Transaction.fromJson(inserted as Map<String, dynamic>), ...list]);
    } else {
      await load();
    }
  }

  Future<void> update(Transaction tx) async {
    if (tx.id == null) return;
    await SupabaseService()
        .client
        .from('transactions')
        .update(tx.toJson())
        .eq('id', tx.id!);
    await load();
  }

  Future<void> delete(String id) async {
    await SupabaseService().client.from('transactions').delete().eq('id', id);
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
