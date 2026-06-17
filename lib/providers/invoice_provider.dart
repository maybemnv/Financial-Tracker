import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase.dart';
import '../models/invoice.dart';

class InvoiceNotifier extends StateNotifier<AsyncValue<List<Invoice>>> {
  InvoiceNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await SupabaseService()
          .client
          .from('invoices')
          .select()
          .order('created_at', ascending: false);
      final invoices = (data as List)
          .map((json) => Invoice.fromJson(json as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(invoices);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(Invoice inv) async {
    await SupabaseService().client.from('invoices').insert(inv.toJson());
    await load();
  }

  Future<void> update(Invoice inv) async {
    await SupabaseService()
        .client
        .from('invoices')
        .update(inv.toJson())
        .eq('id', inv.id!);
    await load();
  }

  Future<void> delete(String id) async {
    await SupabaseService().client.from('invoices').delete().eq('id', id);
    await load();
  }
}

final invoiceProvider =
    StateNotifierProvider<InvoiceNotifier, AsyncValue<List<Invoice>>>((ref) {
  final notifier = InvoiceNotifier();
  notifier.load();
  return notifier;
});
