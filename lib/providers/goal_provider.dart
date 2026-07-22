import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase.dart';
import '../models/goal.dart';
import '../models/goal_contribution.dart';

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

  /// Earmark (or, with a negative [amount], release) money against a goal.
  /// Runs through `contribute_to_goal` so the contribution row and the new
  /// total are written in one transaction — never a read-then-write.
  ///
  /// Allocation is earmarking: no account balance and no net worth changes.
  Future<void> contribute(
    String goalId,
    double amount, {
    String? note,
    bool allowOverfunding = false,
  }) async {
    await SupabaseService().client.rpc('contribute_to_goal', params: {
      'p_goal_id': goalId,
      'p_amount': amount,
      'p_note': note,
      'p_allow_overfunding': allowOverfunding,
    });
    await load();
  }

  /// Move earmarked money between goals as one transaction: a negative row on
  /// the source and a positive row on the target. The combined earmarked total
  /// is conserved.
  Future<void> reallocate({
    required String fromGoalId,
    required String toGoalId,
    required double amount,
    String? note,
    bool allowOverfunding = false,
  }) async {
    await SupabaseService().client.rpc('reallocate_goal_funds', params: {
      'p_from': fromGoalId,
      'p_to': toGoalId,
      'p_amount': amount,
      'p_note': note,
      'p_allow_overfunding': allowOverfunding,
    });
    await load();
  }

  /// Edit name, target, optional target date, and type. Reducing the target
  /// below the earmarked amount requires [allowTargetBelowAllocated].
  Future<void> updateGoal({
    required String goalId,
    required String name,
    required double targetAmount,
    DateTime? targetDate,
    String? type,
    bool allowTargetBelowAllocated = false,
  }) async {
    await SupabaseService().client.rpc('update_goal', params: {
      'p_goal_id': goalId,
      'p_name': name,
      'p_target_amount': targetAmount,
      'p_target_date': targetDate?.toIso8601String().split('T').first,
      'p_type': type,
      'p_allow_target_below_allocated': allowTargetBelowAllocated,
    });
    await load();
  }

  /// Pause, archive, or restore. `completed` is derived from funding and is
  /// rejected by the RPC.
  Future<void> setStatus(String goalId, String status) async {
    await SupabaseService().client.rpc('set_goal_status', params: {
      'p_goal_id': goalId,
      'p_status': status,
    });
    await load();
  }

  /// SOFT delete — never a hard `DELETE`, and refused by the RPC once the goal
  /// has allocation history (archive it instead).
  Future<void> delete(String id) async {
    await SupabaseService().client.rpc('delete_goal', params: {
      'p_goal_id': id,
    });
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

/// Allocation history for one goal, newest first.
final goalContributionsProvider =
    FutureProvider.family<List<GoalContribution>, String>((ref, goalId) async {
  // Re-read whenever a goal changes so history follows the latest write.
  ref.watch(goalProvider);
  final data = await SupabaseService().client
      .from('goal_contributions')
      .select()
      .eq('goal_id', goalId)
      .order('created_at', ascending: false)
      .limit(200);
  return (data as List)
      .map((json) => GoalContribution.fromJson(json as Map<String, dynamic>))
      .toList();
});
