import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../models/transaction_label.dart';

class LabelNotifier extends StateNotifier<AsyncValue<List<TransactionLabel>>> {
  LabelNotifier() : super(const AsyncValue.loading());

  RealtimeChannel? _channel;

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
