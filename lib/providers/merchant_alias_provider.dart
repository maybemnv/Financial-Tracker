import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/supabase.dart';
import '../models/merchant_alias.dart';

class MerchantAliasNotifier
    extends StateNotifier<AsyncValue<List<MerchantAlias>>> {
  MerchantAliasNotifier() : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await SupabaseService()
          .client
          .from('merchant_aliases')
          .select()
          .order('canonical_name');
      state = AsyncValue.data(
        (data as List)
            .map((j) => MerchantAlias.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList(),
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add({
    required String matchPattern,
    required String canonicalName,
  }) async {
    await SupabaseService().client.from('merchant_aliases').insert({
      'match_pattern': matchPattern.trim(),
      'canonical_name': canonicalName.trim(),
    });
    await load();
  }

  Future<void> remove(String id) async {
    await SupabaseService().client
        .from('merchant_aliases')
        .delete()
        .eq('id', id);
    await load();
  }
}

final merchantAliasProvider = StateNotifierProvider<MerchantAliasNotifier,
    AsyncValue<List<MerchantAlias>>>((ref) => MerchantAliasNotifier());
