import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/aggregates.dart';
import '../core/supabase.dart';
import '../models/account.dart';
import 'ledger_provider.dart';

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

/// Derived balance per account, in ONE call (`get_account_balances`).
///
/// Was one `fn_account_balance` round trip per account, driven off the
/// full-ledger provider. Both are gone: the batch RPC replaces the N calls, and
/// watching the paged ledger's row count replaces pulling every transaction
/// into memory just to know when a balance might have changed.
final accountBalancesProvider =
    FutureProvider<Map<String, double>>((ref) async {
  ref.watch(ledgerProvider.select((s) => s.rows.length));
  final result = await SupabaseService().client.rpc('get_account_balances');
  final balances = AccountBalance.listFromRpc(
    Map<String, dynamic>.from(result as Map),
  );
  return {for (final b in balances) b.id: b.balance};
});

/// Net worth across all accounts via `fn_net_worth()`.
///
/// Errors propagate. The previous version swallowed them and returned 0, which
/// renders as a real, catastrophically wrong net worth rather than as a
/// failure — the same "failure becomes an authoritative answer" bug the Agent
/// tools had.
final netWorthProvider = FutureProvider<double>((ref) async {
  ref.watch(ledgerProvider.select((s) => s.rows.length));
  final value = await SupabaseService().client.rpc('fn_net_worth');
  return (value as num?)?.toDouble() ?? 0;
});
