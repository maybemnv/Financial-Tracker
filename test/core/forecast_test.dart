import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/core/cash_forecast.dart';
import 'package:finance_tracker/core/obligations.dart';
import 'package:finance_tracker/models/recurring_expense.dart';
import 'package:finance_tracker/models/recurring_income.dart';

/// Phase 9.3 — obligation statuses across due-date boundaries, and a forecast
/// that can be recomputed by hand from its stated inputs.
void main() {
  final now = DateTime(2026, 7, 23, 14, 30);

  RecurringExpense expense({
    String id = 'e1',
    String name = 'Rent',
    double amount = 1000,
    String frequency = 'monthly',
    DateTime? nextDue,
    bool isPaused = false,
    DateTime? confirmedFor,
  }) =>
      RecurringExpense(
        id: id,
        name: name,
        amount: amount,
        frequency: frequency,
        nextDue: nextDue,
        isPaused: isPaused,
        confirmedFor: confirmedFor,
      );

  RecurringIncome income({
    String id = 'i1',
    String name = 'Salary',
    double amount = 5000,
    String frequency = 'monthly',
    DateTime? nextExpected,
  }) =>
      RecurringIncome(
        id: id,
        name: name,
        amount: amount,
        frequency: frequency,
        nextExpected: nextExpected,
      );

  group('status across due-date boundaries', () {
    test('tomorrow is upcoming, today is today, yesterday is overdue', () {
      final tomorrow =
          Obligation.fromExpense(expense(nextDue: DateTime(2026, 7, 24)), now: now);
      final today =
          Obligation.fromExpense(expense(nextDue: DateTime(2026, 7, 23)), now: now);
      final yesterday =
          Obligation.fromExpense(expense(nextDue: DateTime(2026, 7, 22)), now: now);

      expect(tomorrow.status, ObligationStatus.upcoming);
      expect(today.status, ObligationStatus.today);
      expect(yesterday.status, ObligationStatus.overdue);
    });

    test('the time of day does not shift the boundary', () {
      // 14:30 on the due date is still "today", not overdue.
      final due = Obligation.fromExpense(
          expense(nextDue: DateTime(2026, 7, 23)), now: now);
      expect(due.status, ObligationStatus.today);
      expect(due.daysRemaining, 0);
    });

    test('days remaining goes negative when overdue', () {
      final o = Obligation.fromExpense(
          expense(nextDue: DateTime(2026, 7, 20)), now: now);
      expect(o.daysRemaining, -3);
    });

    test('paused and confirmed are excluded from the forecast', () {
      final paused = Obligation.fromExpense(
          expense(nextDue: DateTime(2026, 7, 24), isPaused: true), now: now);
      final confirmed = Obligation.fromExpense(
        expense(
            nextDue: DateTime(2026, 7, 24),
            confirmedFor: DateTime(2026, 7, 24)),
        now: now,
      );

      expect(paused.status, ObligationStatus.paused);
      expect(confirmed.status, ObligationStatus.confirmed);
      expect(paused.affectsForecast, isFalse);
      expect(confirmed.affectsForecast, isFalse,
          reason: 'A confirmed obligation is already in the ledger; counting '
              'it again double-counts the same money.');
    });

    test('a confirmation for an older cycle does not settle the new one', () {
      final o = Obligation.fromExpense(
        expense(
            nextDue: DateTime(2026, 8, 1),
            confirmedFor: DateTime(2026, 7, 1)),
        now: now,
      );
      expect(o.status, ObligationStatus.upcoming);
      expect(o.affectsForecast, isTrue);
    });
  });

  group('occurrences within the horizon', () {
    test('a weekly obligation lands several times in 30 days', () {
      final o = Obligation.fromExpense(
        expense(frequency: 'weekly', nextDue: DateTime(2026, 7, 24)),
        now: now,
      );
      final dates = o.occurrencesWithin(const Duration(days: 30), now: now);
      expect(dates.length, 5,
          reason: 'Jul 24, 31, Aug 7, 14, 21 — counting it once would '
              'understate outflow by four weeks.');
    });

    test('an overdue obligation is still owed and counts at the window start',
        () {
      final o = Obligation.fromExpense(
        expense(nextDue: DateTime(2026, 7, 10)),
        now: now,
      );
      final dates = o.occurrencesWithin(const Duration(days: 30), now: now);
      expect(dates.first, DateTime(2026, 7, 23));
    });

    test('a paused obligation yields nothing', () {
      final o = Obligation.fromExpense(
        expense(nextDue: DateTime(2026, 7, 24), isPaused: true),
        now: now,
      );
      expect(o.occurrencesWithin(const Duration(days: 30), now: now), isEmpty);
    });
  });

  group('forecast, checked by hand', () {
    const inputs = ForecastInputs(
      liquidBalance: 50000,
      investmentBalance: 200000,
      earmarkedTotal: 30000,
      personalSpendPerDay: 500,
      lookbackDays: 90,
    );

    test('projection is exactly the stated arithmetic', () {
      final obligations = [
        Obligation.fromExpense(
            expense(name: 'Rent', amount: 15000, nextDue: DateTime(2026, 8, 1)),
            now: now),
        Obligation.fromIncome(
            income(
                name: 'Salary',
                amount: 60000,
                nextExpected: DateTime(2026, 7, 31)),
            now: now),
      ];

      final f = CashForecast.project(
          inputs: inputs, obligations: obligations, now: now);

      // By hand: inflow 60000, outflow 15000, discretionary 500 * 30 = 15000.
      // 50000 + 60000 - 15000 - 15000 = 80000.
      expect(f.expectedInflow, 60000);
      expect(f.expectedOutflow, 15000);
      expect(f.estimatedDiscretionarySpend, 15000);
      expect(f.projectedLiquid, 80000);
    });

    test('investment balances are never spendable cash', () {
      final f = CashForecast.project(
          inputs: inputs, obligations: const [], now: now);
      expect(f.openingLiquid, 50000,
          reason: 'The 200000 in investments must not appear here.');
      expect(f.investmentBalance, 200000, reason: 'shown as context only');
      expect(f.projectedLiquid, 50000 - 15000);
    });

    test('earmarked goal money is context, never subtracted', () {
      final f = CashForecast.project(
          inputs: inputs, obligations: const [], now: now);
      expect(f.earmarkedTotal, 30000);
      expect(f.openingLiquid, 50000,
          reason: 'Allocation is earmarking; the money has not left the '
              'account, so subtracting it would report cash the owner still '
              'has as gone.');
    });

    test('safe-to-spend covers only obligations before the next inflow', () {
      final obligations = [
        Obligation.fromExpense(
            expense(id: 'a', name: 'Rent', amount: 15000, nextDue: DateTime(2026, 7, 25)),
            now: now),
        Obligation.fromIncome(
            income(name: 'Salary', amount: 60000, nextExpected: DateTime(2026, 7, 31)),
            now: now),
        Obligation.fromExpense(
            expense(id: 'b', name: 'Insurance', amount: 9000, nextDue: DateTime(2026, 8, 5)),
            now: now),
      ];

      final f = CashForecast.project(
          inputs: inputs, obligations: obligations, now: now);

      expect(f.nextInflowDate, DateTime(2026, 7, 31));
      expect(f.obligationsBeforeNextInflow, 15000,
          reason: 'Insurance falls after the salary lands, so it is not the '
              'money that has to survive until then.');
      expect(f.safeToSpend, 35000);
    });

    test('safe-to-spend floors at zero rather than reporting negative cash',
        () {
      final obligations = [
        Obligation.fromExpense(
            expense(amount: 90000, nextDue: DateTime(2026, 7, 25)), now: now),
      ];
      final f = CashForecast.project(
          inputs: inputs, obligations: obligations, now: now);
      expect(f.safeToSpend, 0);
    });

    test('confirmed obligations are not counted twice', () {
      final obligations = [
        Obligation.fromExpense(
          expense(
              amount: 15000,
              nextDue: DateTime(2026, 7, 25),
              confirmedFor: DateTime(2026, 7, 25)),
          now: now,
        ),
      ];
      final f = CashForecast.project(
          inputs: inputs, obligations: obligations, now: now);
      expect(f.expectedOutflow, 0);
      expect(f.events, isEmpty);
    });

    test('assumptions are stated with the result', () {
      final f = CashForecast.project(
          inputs: inputs, obligations: const [], now: now);
      expect(f.assumptions, isNotEmpty);
      expect(f.assumptions.any((a) => a.contains('Investment balances are excluded')),
          isTrue);
      expect(f.assumptions.any((a) => a.contains('not been subtracted')), isTrue);
      expect(f.assumptions.any((a) => a.contains('not a prediction')), isTrue,
          reason: 'The forecast must present as an estimate, never as '
              'authoritative.');
    });
  });

  group('ordering', () {
    test('soonest first, undated last', () {
      final list = buildObligations(
        expenses: [
          expense(id: 'far', name: 'Far', nextDue: DateTime(2026, 8, 20)),
          expense(id: 'none', name: 'Undated'),
          expense(id: 'soon', name: 'Soon', nextDue: DateTime(2026, 7, 24)),
        ],
        incomes: [],
        now: now,
      );
      expect(list.map((o) => o.name), ['Soon', 'Far', 'Undated']);
    });
  });
}
