import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase.dart';
import '../models/recurring_expense.dart';

/// Known recurring outflows — used by the agent to compute "committed money".
class RecurringExpenseNotifier extends StateNotifier<AsyncValue<List<RecurringExpense>>> {
  RecurringExpenseNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final data = await SupabaseService().client
          .from('recurring_expenses')
          .select()
          .eq('is_deleted', false)
          .order('name', ascending: true);
      final items = (data as List)
          .map((json) => RecurringExpense.fromJson(json as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(RecurringExpense item) async {
    await SupabaseService().client.from('recurring_expenses').insert(item.toJson());
    await load();
  }

}

final recurringExpenseProvider = StateNotifierProvider<RecurringExpenseNotifier,
    AsyncValue<List<RecurringExpense>>>((ref) {
  final notifier = RecurringExpenseNotifier();
  notifier.load();
  return notifier;
});
