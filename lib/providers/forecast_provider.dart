import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cash_forecast.dart';
import '../core/obligations.dart';
import '../core/supabase.dart';
import 'ledger_provider.dart';
import 'recurring_expense_provider.dart';
import 'recurring_income_provider.dart';

/// Recurring rows projected to their next occurrence, ordered by due date.
///
/// Derived in Dart: these tables hold a handful of rows, unlike the ledger, so
/// there is nothing to gain from a server round trip and a lot to gain from the
/// status rules being unit-testable.
final obligationsProvider = Provider<List<Obligation>>((ref) {
  final expenses = ref.watch(recurringExpenseProvider).valueOrNull ?? const [];
  final incomes = ref.watch(recurringIncomeProvider).valueOrNull ?? const [];
  return buildObligations(
    expenses: expenses,
    incomes: incomes,
    now: DateTime.now(),
  );
});

/// Measured inputs only — balances and the observed spend rate.
final forecastInputsProvider = FutureProvider<ForecastInputs>((ref) async {
  ref.watch(ledgerProvider.select((s) => s.rows.length));
  final result =
      await SupabaseService().client.rpc('get_forecast_inputs');
  return ForecastInputs.fromRpc(Map<String, dynamic>.from(result as Map));
});

/// The 30-day projection. Pure arithmetic over the inputs and obligations
/// above, so anything it reports can be checked by hand.
final cashForecastProvider = FutureProvider<CashForecast>((ref) async {
  final inputs = await ref.watch(forecastInputsProvider.future);
  final obligations = ref.watch(obligationsProvider);
  return CashForecast.project(
    inputs: inputs,
    obligations: obligations,
    now: DateTime.now(),
  );
});
