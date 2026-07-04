import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../models/account.dart';
import 'transaction_provider.dart';

class AccountNotifier extends StateNotifier<AsyncValue<List<Account>>> {
  AccountNotifier() : super(const AsyncValue.loading());

  RealtimeChannel? _channel;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await SupabaseService()
          .client
          .from('accounts')
          .select()
          .eq('is_deleted', false)
          .order('created_at', ascending: true);
      final accounts = (data as List)
          .map((json) => Account.fromJson(json as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(accounts);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void subscribe() {
    _channel = SupabaseService()
        .client
        .channel('accounts')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          table: 'accounts',
          callback: (_) => load(),
        )
        .subscribe();
  }

  void unsubscribe() {
    _channel?.unsubscribe();
  }

  Future<void> add(Account account) async {
    await SupabaseService().client.from('accounts').insert(account.toJson());
    await load();
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}

final accountProvider =
    StateNotifierProvider<AccountNotifier, AsyncValue<List<Account>>>((ref) {
  final notifier = AccountNotifier();
  notifier.load();
  notifier.subscribe();
  ref.onDispose(() => notifier.unsubscribe());
  return notifier;
});

/// Derived balance per account via the `fn_account_balance` RPC. Watches the
/// transaction feed so balances refresh whenever money moves.
final accountBalancesProvider =
    FutureProvider<Map<String, double>>((ref) async {
  ref.watch(transactionProvider);
  final accountsAsync = ref.watch(accountProvider);
  return accountsAsync.maybeWhen(
    data: (accounts) async {
      final client = SupabaseService().client;
      final balances = <String, double>{};
      for (final a in accounts) {
        if (a.id == null) continue;
        try {
          final value = await client
              .rpc('fn_account_balance', params: {'p_account_id': a.id});
          balances[a.id!] = (value as num?)?.toDouble() ?? 0;
        } catch (_) {
          balances[a.id!] = 0;
        }
      }
      return balances;
    },
    orElse: () => <String, double>{},
  );
});

/// Net worth across all accounts via `fn_net_worth()`. Watches transactions so
/// the figure refreshes after edits, transfers, and investment moves.
final netWorthProvider = FutureProvider<double>((ref) async {
  ref.watch(accountProvider);
  ref.watch(transactionProvider);
  try {
    final value = await SupabaseService().client.rpc('fn_net_worth');
    return (value as num?)?.toDouble() ?? 0;
  } catch (_) {
    return 0;
  }
});
