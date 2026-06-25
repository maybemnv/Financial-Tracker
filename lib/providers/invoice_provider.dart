import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase.dart';
import '../models/invoice.dart';

class InvoiceNotifier extends StateNotifier<AsyncValue<List<Invoice>>> {
  RealtimeChannel? _channel;

  InvoiceNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await SupabaseService()
          .client
          .from('invoices')
          .select()
          .eq('is_deleted', false)
          .order('created_at', ascending: false)
          .limit(100);
      final invoices = (data as List)
          .map((json) => Invoice.fromJson(json as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(invoices);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void subscribe() {
    _channel = SupabaseService()
        .client
        .channel('invoices')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          table: 'invoices',
          callback: (_) => load(),
        )
        .subscribe();
  }

  void unsubscribe() {
    _channel?.unsubscribe();
  }

  Future<void> add(Invoice inv) async {
    await SupabaseService().client.from('invoices').insert(inv.toJson());
    await load();
  }

  Future<void> update(Invoice inv) async {
    if (inv.id == null) return;
    await SupabaseService()
        .client
        .from('invoices')
        .update(inv.toJson())
        .eq('id', inv.id!);
    await load();
  }

  /// SOFT delete — never a hard `DELETE`.
  Future<void> delete(String id) async {
    await SupabaseService().client.from('invoices').update({
      'is_deleted': true,
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    await load();
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}

final invoiceProvider =
    StateNotifierProvider<InvoiceNotifier, AsyncValue<List<Invoice>>>((ref) {
  final notifier = InvoiceNotifier();
  notifier.load();
  notifier.subscribe();
  ref.onDispose(() => notifier.unsubscribe());
  return notifier;
});
