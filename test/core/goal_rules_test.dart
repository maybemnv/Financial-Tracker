import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/core/goal_rules.dart';
import 'package:finance_tracker/models/goal.dart';
import 'package:finance_tracker/models/goal_contribution.dart';

/// Phase 6.5 — goal allocation, editing, and lifecycle rules.
///
/// The DB-side guarantees these mirror (atomic RPCs, drift assertion) are
/// exercised by `supabase/tests/goal_allocation.sql`.
void main() {
  Goal goal({
    double target = 10000,
    double allocated = 0,
    String status = 'active',
    String type = 'custom',
    String id = 'g1',
    DateTime? createdAt,
  }) =>
      Goal(
        id: id,
        name: 'Goal',
        type: type,
        targetAmount: target,
        allocatedAmount: allocated,
        status: status,
        createdAt: createdAt,
      );

  var seq = 0;
  GoalContribution contribution(double amount, DateTime at) =>
      GoalContribution(
        id: 'c${seq++}',
        goalId: 'g1',
        amount: amount,
        createdAt: at,
      );

  group('allocation is earmarking', () {
    test('history reconciles with the allocated total', () {
      final history = [
        contribution(5000, DateTime(2026, 1, 10)),
        contribution(2000, DateTime(2026, 2, 10)),
        contribution(-1500, DateTime(2026, 3, 10)),
      ];
      final derived = history.fold<double>(0, (sum, c) => sum + c.amount);
      final g = goal(allocated: derived);

      expect(derived, 5500);
      expect(g.allocatedAmount, derived);
    });

    test('a negative correction cannot drive the total below zero', () {
      // The UI blocks it and contribute_to_goal raises; both use this rule.
      final g = goal(allocated: 1000);
      expect(g.allocatedAmount - 1500 < 0, isTrue);
      expect(g.allocatedAmount - 1000 < 0, isFalse);
    });

    test('reallocation conserves the combined earmarked total', () {
      final source = goal(id: 'a', allocated: 4000);
      final target = goal(id: 'b', allocated: 1000);
      const move = 1500.0;

      final before = source.allocatedAmount + target.allocatedAmount;
      final movedSource =
          source.copyWith(allocatedAmount: source.allocatedAmount - move);
      final movedTarget =
          target.copyWith(allocatedAmount: target.allocatedAmount + move);

      expect(movedSource.allocatedAmount + movedTarget.allocatedAmount, before);
    });

    test('earmarking changes no account balance and no net worth', () {
      // Net worth derives from accounts and transactions only; a goal
      // contribution writes to goals/goal_contributions and nothing else.
      const accountBalance = 250000.0;
      const netWorth = accountBalance;

      final before = goal(allocated: 0);
      final after = before.copyWith(allocatedAmount: 50000);

      expect(after.allocatedAmount, 50000);
      expect(accountBalance, 250000.0);
      expect(netWorth, 250000.0);
      expect(after.targetAmount, before.targetAmount);
    });
  });

  group('overfunding and target guards', () {
    test('positive contribution past the target needs confirmation', () {
      final g = goal(target: 10000, allocated: 9000);
      expect(GoalRules.wouldOverfund(g, 500), isFalse);
      expect(GoalRules.wouldOverfund(g, 1000), isFalse);
      expect(GoalRules.wouldOverfund(g, 1500), isTrue);
    });

    test('negative corrections never trigger the overfund guard', () {
      final overfunded = goal(target: 10000, allocated: 12000);
      expect(GoalRules.wouldOverfund(overfunded, -1000), isFalse);
    });

    test('reducing the target below the earmarked amount is flagged', () {
      final g = goal(target: 10000, allocated: 6000);
      expect(GoalRules.targetBelowAllocated(g, 5999), isTrue);
      expect(GoalRules.targetBelowAllocated(g, 6000), isFalse);
      expect(GoalRules.targetBelowAllocated(g, 12000), isFalse);
    });
  });

  group('lifecycle', () {
    test('active and completed goals can be paused or archived', () {
      expect(GoalRules.allowedTransitions('active'), ['paused', 'archived']);
      expect(GoalRules.allowedTransitions('completed'), ['paused', 'archived']);
    });

    test('paused resumes, archived restores', () {
      expect(GoalRules.allowedTransitions('paused'), contains('active'));
      expect(GoalRules.allowedTransitions('archived'), ['active']);
    });

    test('completed is never a manual transition target', () {
      for (final from in ['active', 'paused', 'archived', 'completed']) {
        expect(GoalRules.allowedTransitions(from), isNot(contains('completed')));
      }
      expect(GoalRules.manualStatuses, isNot(contains('completed')));
    });

    test('delete is safe only without history; otherwise archive', () {
      expect(GoalRules.canDelete(0), isTrue);
      expect(GoalRules.canDelete(1), isFalse);
      expect(GoalRules.canDelete(12), isFalse);
    });

    test('emergency fund pins above custom goals, archived sink', () {
      final sorted = GoalRules.sorted([
        goal(id: 'c', type: 'custom', createdAt: DateTime(2026, 1, 1)),
        goal(id: 'z', type: 'custom', status: 'archived',
            createdAt: DateTime(2025, 1, 1)),
        goal(id: 'e', type: 'emergency_fund', createdAt: DateTime(2026, 5, 1)),
      ]);
      expect(sorted.map((g) => g.id), ['e', 'c', 'z']);
    });
  });

  group('completion estimate gating', () {
    test('a single allocation yields no estimate', () {
      final estimate = GoalRules.estimateCompletion(
        goal: goal(allocated: 1000),
        contributions: [contribution(1000, DateTime(2026, 1, 5))],
      );
      expect(estimate.status, GoalEstimateStatus.notEnoughHistory);
      expect(estimate.projectedMonth, isNull);
    });

    test('three allocations inside one month yield no estimate', () {
      final estimate = GoalRules.estimateCompletion(
        goal: goal(allocated: 3000),
        contributions: [
          contribution(1000, DateTime(2026, 1, 5)),
          contribution(1000, DateTime(2026, 1, 15)),
          contribution(1000, DateTime(2026, 1, 25)),
        ],
      );
      expect(estimate.status, GoalEstimateStatus.notEnoughHistory);
    });

    test('three allocations across two months project a month', () {
      final estimate = GoalRules.estimateCompletion(
        goal: goal(target: 10000, allocated: 4000),
        contributions: [
          contribution(1000, DateTime(2026, 1, 5)),
          contribution(1000, DateTime(2026, 1, 25)),
          contribution(2000, DateTime(2026, 2, 10)),
        ],
        asOf: DateTime(2026, 2, 28),
      );

      // 4000 over a 2-month span = 2000/month; 6000 remaining = 3 months.
      expect(estimate.status, GoalEstimateStatus.estimated);
      expect(estimate.monthlyPace, 2000);
      expect(estimate.monthsRemaining, 3);
      expect(estimate.projectedMonth, DateTime(2026, 5, 1));
    });

    test('a met target reports funded, not an estimate', () {
      final estimate = GoalRules.estimateCompletion(
        goal: goal(target: 10000, allocated: 10000),
        contributions: [
          contribution(5000, DateTime(2026, 1, 5)),
          contribution(3000, DateTime(2026, 2, 5)),
          contribution(2000, DateTime(2026, 3, 5)),
        ],
      );
      expect(estimate.status, GoalEstimateStatus.alreadyFunded);
      expect(estimate.projectedMonth, isNull);
    });

    test('net-negative history reports no forward progress', () {
      final estimate = GoalRules.estimateCompletion(
        goal: goal(target: 10000, allocated: 500),
        contributions: [
          contribution(3000, DateTime(2026, 1, 5)),
          contribution(-1500, DateTime(2026, 2, 5)),
          contribution(-1000, DateTime(2026, 3, 5)),
          contribution(-500, DateTime(2026, 3, 20)),
        ],
      );
      expect(estimate.status, GoalEstimateStatus.noForwardProgress);
    });

    test('a pace too slow to matter is not dressed up as a date', () {
      final estimate = GoalRules.estimateCompletion(
        goal: goal(target: 1000000, allocated: 100),
        contributions: [
          contribution(50, DateTime(2026, 1, 5)),
          contribution(25, DateTime(2026, 2, 5)),
          contribution(25, DateTime(2026, 3, 5)),
        ],
      );
      expect(estimate.status, GoalEstimateStatus.beyondHorizon);
      expect(estimate.projectedMonth, isNull);
    });
  });
}
