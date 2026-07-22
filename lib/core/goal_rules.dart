import '../models/goal.dart';
import '../models/goal_contribution.dart';

/// Why a completion estimate is or is not being shown.
enum GoalEstimateStatus {
  /// Enough history to project a completion month.
  estimated,

  /// The target is already met — nothing left to project.
  alreadyFunded,

  /// Fewer than 3 contributions, or all of them inside a single month.
  notEnoughHistory,

  /// History exists but the net pace is zero or negative.
  noForwardProgress,

  /// The pace is positive but so slow the projection is meaningless.
  beyondHorizon,
}

/// Result of projecting a goal's completion from its contribution history.
class GoalCompletionEstimate {
  const GoalCompletionEstimate({
    required this.status,
    this.monthlyPace = 0,
    this.monthsRemaining = 0,
    this.projectedMonth,
  });

  final GoalEstimateStatus status;

  /// Net earmarked amount per month across the observed history.
  final double monthlyPace;

  /// Whole months until the target is met at [monthlyPace].
  final int monthsRemaining;

  /// First day of the projected completion month; null unless [hasEstimate].
  final DateTime? projectedMonth;

  bool get hasEstimate => status == GoalEstimateStatus.estimated;
}

/// Pure decision rules for goal editing, lifecycle, and projection (PRD §6 /
/// TODO 6.2–6.3). Kept free of Supabase and Flutter so every guard the UI
/// shows is unit-testable; the same guards are enforced again in migration
/// 00015 so they cannot be bypassed by calling the API directly.
class GoalRules {
  GoalRules._();

  /// Projection needs at least this many contributions...
  static const int minContributions = 3;

  /// ...spread across at least this many distinct calendar months.
  static const int minDistinctMonths = 2;

  /// Longest projection worth showing, in months.
  static const int horizonMonths = 600;

  /// Statuses the owner may set by hand. `completed` is derived from funding
  /// and is never chosen manually.
  static const Set<String> manualStatuses = {'active', 'paused', 'archived'};

  /// Statuses reachable from [current] through the UI.
  static List<String> allowedTransitions(String current) {
    switch (current) {
      case 'active':
      case 'completed':
        return const ['paused', 'archived'];
      case 'paused':
        return const ['active', 'archived'];
      case 'archived':
        return const ['active'];
      default:
        return const [];
    }
  }

  /// True when a positive contribution would push the goal past its target.
  /// Negative corrections never need overfund confirmation, even on a goal
  /// that is already overfunded.
  static bool wouldOverfund(Goal goal, double amount) {
    if (amount <= 0) return false;
    return goal.allocatedAmount + amount > goal.targetAmount;
  }

  /// True when the edited target would sit below money already earmarked.
  static bool targetBelowAllocated(Goal goal, double newTarget) =>
      newTarget < goal.allocatedAmount;

  /// A goal may be soft-deleted only while it carries no history; otherwise
  /// the audit trail must survive and the owner archives instead.
  static bool canDelete(int contributionCount) => contributionCount == 0;

  /// Emergency Fund pinned on top (by [Goal.type], so it can be renamed
  /// freely), archived goals sunk to the bottom, then oldest first.
  static List<Goal> sorted(Iterable<Goal> goals) {
    final copy = [...goals];
    copy.sort((a, b) {
      if (a.isEmergencyFund != b.isEmergencyFund) {
        return a.isEmergencyFund ? -1 : 1;
      }
      if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
      final aAt = a.createdAt;
      final bAt = b.createdAt;
      if (aAt != null && bAt != null) return aAt.compareTo(bAt);
      return 0;
    });
    return copy;
  }

  /// Projects when [goal] reaches its target from the observed contribution
  /// pace. Deliberately conservative: a single allocation (or a single month
  /// of them) yields [GoalEstimateStatus.notEnoughHistory] rather than a
  /// confident-looking date drawn from one data point.
  static GoalCompletionEstimate estimateCompletion({
    required Goal goal,
    required List<GoalContribution> contributions,
    DateTime? asOf,
  }) {
    if (goal.remaining <= 0) {
      return const GoalCompletionEstimate(
        status: GoalEstimateStatus.alreadyFunded,
      );
    }
    if (contributions.length < minContributions) {
      return const GoalCompletionEstimate(
        status: GoalEstimateStatus.notEnoughHistory,
      );
    }

    final months = <int>{};
    var earliest = contributions.first.createdAt;
    var latest = contributions.first.createdAt;
    var total = 0.0;
    for (final c in contributions) {
      months.add(c.createdAt.year * 12 + c.createdAt.month);
      if (c.createdAt.isBefore(earliest)) earliest = c.createdAt;
      if (c.createdAt.isAfter(latest)) latest = c.createdAt;
      total += c.amount;
    }
    if (months.length < minDistinctMonths) {
      return const GoalCompletionEstimate(
        status: GoalEstimateStatus.notEnoughHistory,
      );
    }

    final spanMonths = (latest.year * 12 + latest.month) -
        (earliest.year * 12 + earliest.month) +
        1;
    final pace = total / spanMonths;
    if (pace <= 0) {
      return const GoalCompletionEstimate(
        status: GoalEstimateStatus.noForwardProgress,
      );
    }

    final monthsRemaining = (goal.remaining / pace).ceil();
    if (monthsRemaining > horizonMonths) {
      return GoalCompletionEstimate(
        status: GoalEstimateStatus.beyondHorizon,
        monthlyPace: pace,
        monthsRemaining: monthsRemaining,
      );
    }

    final from = asOf ?? DateTime.now();
    return GoalCompletionEstimate(
      status: GoalEstimateStatus.estimated,
      monthlyPace: pace,
      monthsRemaining: monthsRemaining,
      // Month granularity — an estimate should not imply a specific day.
      projectedMonth: DateTime(from.year, from.month + monthsRemaining, 1),
    );
  }
}
