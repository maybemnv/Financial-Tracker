import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase.dart';
import '../models/recurring_income.dart';

/// Expected recurring inflows. Projected next-expected income is computed
/// client-side from these rows + their frequency.
class RecurringIncomeNotifier extends StateNotifier<AsyncValue<List<RecurringIncome>>> {
  RecurringIncomeNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await SupabaseService().client
          .from('recurring_income')
          .select()
          .eq('is_deleted', false)
          .order('name', ascending: true);
      final items = (data as List)
          .map((json) => RecurringIncome.fromJson(json as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(RecurringIncome item) async {
    await SupabaseService().client.from('recurring_income').insert(item.toJson());
    await load();
  }

}

final recurringIncomeProvider = StateNotifierProvider<RecurringIncomeNotifier,
    AsyncValue<List<RecurringIncome>>>((ref) {
  final notifier = RecurringIncomeNotifier();
  notifier.load();
  return notifier;
});
