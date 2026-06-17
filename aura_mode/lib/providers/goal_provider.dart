import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase.dart';
import '../models/goal.dart';

class GoalNotifier extends StateNotifier<AsyncValue<List<Goal>>> {
  GoalNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await SupabaseService().client.from('goals').select();
      final goals = (data as List)
          .map((json) => Goal.fromJson(json as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(goals);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(Goal goal) async {
    await SupabaseService().client.from('goals').insert(goal.toJson());
    await load();
  }

  Future<void> allocate(String id, double amount) async {
    final current = await SupabaseService()
        .client
        .from('goals')
        .select()
        .eq('id', id)
        .single() as Map<String, dynamic>;
    final existing = (current['allocated_amount'] as num?)?.toDouble() ?? 0;
    await SupabaseService()
        .client
        .from('goals')
        .update({'allocated_amount': existing + amount})
        .eq('id', id);
    await load();
  }
}

final goalProvider =
    StateNotifierProvider<GoalNotifier, AsyncValue<List<Goal>>>((ref) {
  final notifier = GoalNotifier();
  notifier.load();
  return notifier;
});
