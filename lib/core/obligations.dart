import '../models/recurring_expense.dart';
import '../models/recurring_income.dart';

/// Where an obligation sits relative to today (TODO 9.1).
enum ObligationStatus {
  /// Due in the future.
  upcoming,

  /// Due today.
  today,

  /// The due date has passed with no confirmed transaction.
  overdue,

  /// A ledger transaction has been linked to this cycle.
  confirmed,

  /// Paused by the owner; excluded from the forecast.
  paused,
}

/// A recurring inflow or outflow, projected to its next occurrence.
///
/// Deliberately not a new "subscriptions" concept — it is a view over the
/// `recurring_expenses` / `recurring_income` rows that already exist.
class Obligation {
  const Obligation({
    required this.id,
    required this.kind,
    required this.name,
    required this.amount,
    required this.frequency,
    required this.status,
    this.dueDate,
    this.accountId,
    this.daysRemaining,
  });

  final String id;

  /// `expense` (money out) or `income` (money in).
  final String kind;
  final String name;
  final double amount;
  final String frequency;
  final DateTime? dueDate;
  final String? accountId;
  final ObligationStatus status;

  /// Negative when overdue. Null when no due date is recorded.
  final int? daysRemaining;

  bool get isExpense => kind == 'expense';

  /// Counted by the forecast: not paused, not already settled.
  bool get affectsForecast =>
      status != ObligationStatus.paused && status != ObligationStatus.confirmed;

  /// Signed effect on cash.
  double get signedAmount => isExpense ? -amount : amount;

  static ObligationStatus _status({
    required DateTime? due,
    required DateTime today,
    required bool isPaused,
    required bool isConfirmedForThisCycle,
  }) {
    if (isPaused) return ObligationStatus.paused;
    if (isConfirmedForThisCycle) return ObligationStatus.confirmed;
    if (due == null) return ObligationStatus.upcoming;
    final d = DateTime(due.year, due.month, due.day);
    if (d.isAtSameMomentAs(today)) return ObligationStatus.today;
    return d.isBefore(today)
        ? ObligationStatus.overdue
        : ObligationStatus.upcoming;
  }

  static int? _daysRemaining(DateTime? due, DateTime today) {
    if (due == null) return null;
    return DateTime(due.year, due.month, due.day).difference(today).inDays;
  }

  factory Obligation.fromExpense(RecurringExpense e, {required DateTime now}) {
    final today = DateTime(now.year, now.month, now.day);
    return Obligation(
      id: e.id ?? '',
      kind: 'expense',
      name: e.name,
      amount: e.amount,
      frequency: e.frequency,
      dueDate: e.nextDue,
      accountId: e.accountId,
      daysRemaining: _daysRemaining(e.nextDue, today),
      status: _status(
        due: e.nextDue,
        today: today,
        isPaused: e.isPaused,
        isConfirmedForThisCycle:
            e.confirmedFor != null && e.nextDue != null &&
                !e.confirmedFor!.isBefore(e.nextDue!),
      ),
    );
  }

  factory Obligation.fromIncome(RecurringIncome i, {required DateTime now}) {
    final today = DateTime(now.year, now.month, now.day);
    return Obligation(
      id: i.id ?? '',
      kind: 'income',
      name: i.name,
      amount: i.amount,
      frequency: i.frequency,
      dueDate: i.nextExpected,
      accountId: i.accountId,
      daysRemaining: _daysRemaining(i.nextExpected, today),
      status: _status(
        due: i.nextExpected,
        today: today,
        isPaused: i.isPaused,
        isConfirmedForThisCycle:
            i.confirmedFor != null && i.nextExpected != null &&
                !i.confirmedFor!.isBefore(i.nextExpected!),
      ),
    );
  }

  /// The next occurrence after [from]. Mirrors `app_advance_due` in `00019`,
  /// so a projected date and a confirmed one never disagree.
  static DateTime advance(DateTime from, String frequency) =>
      switch (frequency.toLowerCase()) {
        'weekly' => from.add(const Duration(days: 7)),
        'yearly' => DateTime(from.year + 1, from.month, from.day),
        _ => DateTime(from.year, from.month + 1, from.day),
      };

  /// Every occurrence falling in `(now, now + horizon]`.
  ///
  /// A weekly obligation can land several times inside a 30-day window, and a
  /// forecast that counted it once would understate outflow.
  List<DateTime> occurrencesWithin(Duration horizon, {required DateTime now}) {
    if (!affectsForecast) return const [];
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(horizon);
    var cursor = dueDate == null
        ? null
        : DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    if (cursor == null) return const [];

    // An overdue obligation is still owed: count it at the start of the window.
    if (cursor.isBefore(today)) cursor = today;

    final dates = <DateTime>[];
    // Bounded so a malformed frequency cannot spin.
    for (var i = 0; i < 64 && !cursor!.isAfter(end); i++) {
      dates.add(cursor);
      cursor = advance(cursor, frequency);
    }
    return dates;
  }
}

/// Builds the obligation list, ordered by due date with undated rows last.
List<Obligation> buildObligations({
  required Iterable<RecurringExpense> expenses,
  required Iterable<RecurringIncome> incomes,
  required DateTime now,
}) {
  final list = <Obligation>[
    for (final e in expenses)
      if (!e.isDeleted) Obligation.fromExpense(e, now: now),
    for (final i in incomes)
      if (!i.isDeleted) Obligation.fromIncome(i, now: now),
  ];
  list.sort((a, b) {
    final ad = a.dueDate;
    final bd = b.dueDate;
    if (ad == null && bd == null) return a.name.compareTo(b.name);
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
  });
  return list;
}
