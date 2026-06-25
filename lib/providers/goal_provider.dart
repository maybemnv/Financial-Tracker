import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase.dart';
import '../models/goal.dart';

class GoalNotifier extends StateNotifier<AsyncValue<List<Goal>>> {
  RealtimeChannel? _channel;

  GoalNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await SupabaseService().client
          .from('goals')
          .select()
          .eq('is_deleted', false)
          .limit(100);
      final goals = (data as List)
          .map((json) => Goal.fromJson(json as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(goals);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void subscribe() {
    _channel = SupabaseService()
        .client
        .channel('goals')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          table: 'goals',
          callback: (_) => load(),
        )
        .subscribe();
  }

  void unsubscribe() {
    _channel?.unsubscribe();
  }

  Future<void> add(Goal goal) async {
    await SupabaseService().client.from('goals').insert(goal.toJson());
    await load();
  }

  Future<void> allocate(String id, double amount) async {
    try {
      final current = await SupabaseService()
          .client
          .from('goals')
          .select()
          .eq('id', id)
          .single();
      final existing = (current['allocated_amount'] as num?)?.toDouble() ?? 0;
      await SupabaseService()
          .client
          .from('goals')
          .update({'allocated_amount': existing + amount})
          .eq('id', id);
      await load();
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  /// SOFT delete — never a hard `DELETE`.
  Future<void> delete(String id) async {
    await SupabaseService().client.from('goals').update({
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

final goalProvider =
    StateNotifierProvider<GoalNotifier, AsyncValue<List<Goal>>>((ref) {
  final notifier = GoalNotifier();
  notifier.load();
  notifier.subscribe();
  ref.onDispose(() => notifier.unsubscribe());
  return notifier;
});
