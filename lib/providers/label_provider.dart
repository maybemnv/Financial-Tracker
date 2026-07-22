import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../models/transaction_label.dart';

class LabelNotifier extends StateNotifier<AsyncValue<List<TransactionLabel>>> {
  LabelNotifier() : super(const AsyncValue.loading());

  RealtimeChannel? _channel;

  /// Loads every label regardless of status. Archived and merged labels stay
  /// readable so historical attribution and the management screen keep working;
  /// [assignableLabelProvider] is what pickers use.
  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await SupabaseService()
          .client
          .from('labels')
          .select()
          .order('name');
      state = AsyncValue.data(
        (data as List)
            .map((json) =>
                TransactionLabel.fromJson(Map<String, dynamic>.from(json as Map)))
            .toList(),
      );
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  void subscribe() {
    _channel = SupabaseService()
        .client
        .channel('labels')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          table: 'labels',
          callback: (_) => load(),
        )
        .subscribe();
  }

  Future<TransactionLabel> create({
    required String name,
    required String color,
  }) async {
    final inserted = await SupabaseService()
        .client
        .from('labels')
        .insert({'name': name.trim(), 'color': color})
        .select()
        .single();
    final label = TransactionLabel.fromJson(
      Map<String, dynamic>.from(inserted),
    );
    state = state.whenData((labels) => [...labels, label]
      ..sort((a, b) => a.name.compareTo(b.name)));
    return label;
  }

  /// Identity-preserving rename: the row keeps its id, so every existing
  /// attachment and every historical attribution follows the new name.
  /// Conflicts are detected case-insensitively among active labels; a
  /// case-only rename of the same label is allowed.
  Future<void> rename(String id, String name) async {
    await SupabaseService()
        .client
        .rpc('rename_label', params: {'p_id': id, 'p_name': name.trim()});
    await load();
  }

  /// Archive or restore. Archived labels stop being assignable but remain
  /// attached to, and reportable on, every transaction that already uses them.
  Future<void> setStatus(String id, String status) async {
    await SupabaseService()
        .client
        .rpc('set_label_status', params: {'p_id': id, 'p_status': status});
    await load();
  }

  /// Moves every contextual and primary reference from source to target in one
  /// transaction, resolving duplicate joins, then marks the source `merged`.
  /// Idempotent if the source was already merged.
  Future<void> merge({required String sourceId, required String targetId}) async {
    await SupabaseService().client.rpc(
      'merge_labels',
      params: {'p_source': sourceId, 'p_target': targetId},
    );
    await load();
  }

  /// SOFT delete, and only for a label nothing references — the RPC raises
  /// otherwise so an attribution can never be orphaned. Never a physical
  /// `DELETE`.
  Future<void> delete(String id) async {
    await SupabaseService().client.rpc('delete_label', params: {'p_id': id});
    await load();
  }

  void unsubscribe() => _channel?.unsubscribe();

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}

final labelProvider =
    StateNotifierProvider<LabelNotifier, AsyncValue<List<TransactionLabel>>>(
  (ref) {
    final notifier = LabelNotifier();
    notifier.load();
    notifier.subscribe();
    ref.onDispose(notifier.unsubscribe);
    return notifier;
  },
);

/// Labels that may be attached to a transaction. `save_transaction_with_labels`
/// rejects anything else, so pickers must not offer archived or merged labels.
final assignableLabelProvider = Provider<List<TransactionLabel>>((ref) {
  final labels = ref.watch(labelProvider).valueOrNull ?? const [];
  return labels.where((l) => l.isAssignable).toList(growable: false);
});

// Per-label usage counts and the review queue moved to owner-scoped aggregate
// RPCs in Phase 7 (`labelUsageStatsProvider`, `reviewBucketProvider` in
// aggregate_provider.dart). Deriving them from provider state would now count
// only the loaded page, silently understating both.
