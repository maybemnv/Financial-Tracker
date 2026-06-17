import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase.dart';
import '../models/transaction.dart';

class TransactionNotifier extends StateNotifier<AsyncValue<List<Transaction>>> {
  TransactionNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await SupabaseService().client
          .from('transactions')
          .select()
          .order('created_at', ascending: false);
      final transactions = (data as List)
          .map((json) => Transaction.fromJson(json as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(transactions);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(Transaction tx) async {
    await SupabaseService().client.from('transactions').insert(tx.toJson());
    await load();
  }

  Future<void> update(Transaction tx) async {
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
}

final transactionProvider =
    StateNotifierProvider<TransactionNotifier, AsyncValue<List<Transaction>>>((ref) {
  final notifier = TransactionNotifier();
  notifier.load();
  return notifier;
});
