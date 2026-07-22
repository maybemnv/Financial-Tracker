import '../models/transaction.dart';
import 'finance_metrics.dart';

class DashboardAnalytics {
  DashboardAnalytics({
    required this.availableMonths,
    required this.currentMonth,
    required this.monthlyTrend,
    required this.dailyFlow,
    required this.spendingCategories,
    required this.totalTransactions,
    required this.uncategorizedTransactions,
    this.latestTransactionAt,
  });

  final List<DateTime> availableMonths;
  final DashboardPeriodSummary currentMonth;
  final List<DashboardMonthlyPoint> monthlyTrend;
  final List<DashboardDailyPoint> dailyFlow;
  final List<DashboardCategoryPoint> spendingCategories;
  final int totalTransactions;
  final int uncategorizedTransactions;
  final DateTime? latestTransactionAt;

  static DashboardAnalytics fromTransactions(
    List<Transaction> transactions, {
    DateTime? focusMonth,
    DateTime? now,
    int monthWindow = 6,
  }) {
    final resolvedNow = now ?? DateTime.now();
    final selectedMonth = _monthStart(focusMonth ?? resolvedNow);
    final monthStart = selectedMonth;
    final nextMonthStart =
        DateTime(selectedMonth.year, selectedMonth.month + 1);
    final availableMonths = monthsForTransactions(transactions);

    final currentMonthTransactions = transactions.where((transaction) {
      final date = _monthStart(transaction.effectiveDate);
      return !date.isBefore(monthStart) && date.isBefore(nextMonthStart);
    }).toList()
      ..sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));

    var monthIncome = 0.0;
    var monthSpending = 0.0;
    var monthFamilySupport = 0.0;
    var monthInvestments = 0.0;
    var monthUncategorized = 0;
    final labelTotals = <String, _LabelTotal>{};
    final dailyTotals = <DateTime, _DailyAccumulator>{};

    for (final transaction in currentMonthTransactions) {
      final effectiveDate = transaction.effectiveDate;
      final dayKey = DateTime(
        effectiveDate.year,
        effectiveDate.month,
        effectiveDate.day,
      );
      final daily = dailyTotals.putIfAbsent(dayKey, _DailyAccumulator.new);

      if (FinanceMetrics.isIncome(transaction)) {
        monthIncome += transaction.amount;
        daily.income += transaction.amount;
      } else if (FinanceMetrics.isExpense(transaction)) {
        monthSpending += transaction.amount;
        daily.spending += transaction.amount;
        if (FinanceMetrics.isFamilySupport(transaction)) {
          monthFamilySupport += transaction.amount;
        }

        // Attribute the FULL amount to exactly one bucket (no even-split, D3):
        // the primary label, else Unlabeled / Needs primary label.
        final status = FinanceMetrics.primaryStatus(transaction);
        switch (status) {
          case PrimaryLabelStatus.resolved:
            final primary = transaction.primaryLabel!;
            labelTotals.update(
              primary.name,
              (value) => value..amount += transaction.amount,
              ifAbsent: () => _LabelTotal(
                amount: transaction.amount,
                color: primary.color,
              ),
            );
            break;
          case PrimaryLabelStatus.unlabeled:
            labelTotals.update(
              'Unlabeled',
              (value) => value..amount += transaction.amount,
              ifAbsent: () => _LabelTotal(amount: transaction.amount),
            );
            monthUncategorized += 1;
            break;
          case PrimaryLabelStatus.needsPrimaryLabel:
            labelTotals.update(
              'Needs primary label',
              (value) => value..amount += transaction.amount,
              ifAbsent: () => _LabelTotal(amount: transaction.amount),
            );
            break;
          case PrimaryLabelStatus.notRequired:
            break;
        }
      } else if (FinanceMetrics.isInvestmentOutflow(transaction)) {
        monthInvestments += transaction.amount;
      }
    }

    final spendingCategories = labelTotals.entries
        .map(
          (entry) => DashboardCategoryPoint(
            label: entry.key,
            amount: entry.value.amount,
            color: entry.value.color,
            share: monthSpending == 0 ? 0 : entry.value.amount / monthSpending,
          ),
        )
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    final dailyFlow = List.generate(
      _daysInMonth(selectedMonth),
      (index) {
        final day =
            DateTime(selectedMonth.year, selectedMonth.month, index + 1);
        final totals = dailyTotals[day];
        return DashboardDailyPoint(
          day: day,
          income: totals?.income ?? 0,
          spending: totals?.spending ?? 0,
        );
      },
    );

    final monthKeys = List.generate(
      monthWindow,
      (index) => DateTime(
        selectedMonth.year,
        selectedMonth.month - (monthWindow - index - 1),
      ),
    );

    final monthMap = <DateTime, _MonthlyAccumulator>{
      for (final key in monthKeys) key: _MonthlyAccumulator(),
    };

    for (final transaction in transactions) {
      final effectiveDate = transaction.effectiveDate;
      final key = DateTime(effectiveDate.year, effectiveDate.month);
      final bucket = monthMap[key];
      if (bucket == null) continue;

      if (FinanceMetrics.isIncome(transaction)) {
        bucket.income += transaction.amount;
      } else if (FinanceMetrics.isExpense(transaction)) {
        bucket.spending += transaction.amount;
      } else if (FinanceMetrics.isInvestmentOutflow(transaction)) {
        bucket.investments += transaction.amount;
      }
    }

    final monthlyTrend = monthKeys.map((key) {
      final bucket = monthMap[key] ?? _MonthlyAccumulator();
      return DashboardMonthlyPoint(
        month: key,
        income: bucket.income,
        spending: bucket.spending,
        investments: bucket.investments,
      );
    }).toList();

    final savings = monthIncome - monthSpending;
    final elapsedDays = selectedMonth.year == resolvedNow.year &&
            selectedMonth.month == resolvedNow.month
        ? resolvedNow.day
        : _daysInMonth(selectedMonth);
    final double averageDailySpending =
        elapsedDays == 0 ? 0.0 : monthSpending / elapsedDays;
    final double projectedSpending =
        (averageDailySpending * _daysInMonth(selectedMonth)).toDouble();

    return DashboardAnalytics(
      availableMonths: availableMonths,
      currentMonth: DashboardPeriodSummary(
        month: monthStart,
        income: monthIncome,
        spending: monthSpending,
        familySupport: monthFamilySupport,
        investments: monthInvestments,
        savings: savings,
        savingsRate: monthIncome == 0 ? 0 : (savings / monthIncome) * 100,
        transactionCount: currentMonthTransactions.length,
        uncategorizedCount: monthUncategorized,
        averageDailySpending: averageDailySpending,
        projectedSpending: projectedSpending,
      ),
      monthlyTrend: monthlyTrend,
      dailyFlow: dailyFlow,
      spendingCategories: spendingCategories,
      totalTransactions: transactions.length,
      uncategorizedTransactions: transactions
          .where((transaction) => FinanceMetrics.isExpense(transaction))
          .where((transaction) => transaction.labels.isEmpty)
          .length,
      latestTransactionAt: transactions.isEmpty
          ? null
          : transactions
              .map((transaction) => transaction.effectiveDate)
              .reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }

  static List<DateTime> monthsForTransactions(List<Transaction> transactions) {
    final months = transactions
        .map((transaction) => _monthStart(transaction.effectiveDate))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return months;
  }
}

class DashboardPeriodSummary {
  DashboardPeriodSummary({
    required this.month,
    required this.income,
    required this.spending,
    required this.investments,
    required this.savings,
    required this.savingsRate,
    required this.transactionCount,
    required this.uncategorizedCount,
    required this.averageDailySpending,
    required this.projectedSpending,
    this.familySupport = 0,
  });

  final DateTime month;
  final double income;

  /// Total Outflow (PRD §4 #2) — Personal Spend plus Family Support.
  final double spending;

  /// Family Support (PRD §4 #4) — excluded from Personal Spend, part of outflow.
  final double familySupport;
  final double investments;
  final double savings;
  final double savingsRate;
  final int transactionCount;
  final int uncategorizedCount;
  final double averageDailySpending;
  final double projectedSpending;

  /// Personal Spend (PRD §4 #3) = Total Outflow − Family Support.
  double get personalSpend => spending - familySupport;

  /// Personal Savings After Own Spend (PRD §4 #8) — context only, NOT kept.
  double get personalSavingsAfterOwnSpend => income - personalSpend;

  double get categorizedRatio {
    if (transactionCount == 0) return 1;
    return (transactionCount - uncategorizedCount) / transactionCount;
  }
}

class DashboardMonthlyPoint {
  DashboardMonthlyPoint({
    required this.month,
    required this.income,
    required this.spending,
    required this.investments,
  });

  final DateTime month;
  final double income;
  final double spending;
  final double investments;

  double get savings => income - spending;
}

class DashboardDailyPoint {
  DashboardDailyPoint({
    required this.day,
    required this.income,
    required this.spending,
  });

  final DateTime day;
  final double income;
  final double spending;
}

class DashboardCategoryPoint {
  DashboardCategoryPoint({
    required this.label,
    required this.amount,
    required this.share,
    this.color,
  });

  final String label;
  final double amount;
  final double share;
  final String? color;
}

class _LabelTotal {
  _LabelTotal({required this.amount, this.color});

  double amount;
  final String? color;
}

class _MonthlyAccumulator {
  double income = 0;
  double spending = 0;
  double investments = 0;
}

class _DailyAccumulator {
  double income = 0;
  double spending = 0;
}

int _daysInMonth(DateTime date) => DateTime(date.year, date.month + 1, 0).day;

DateTime _monthStart(DateTime date) => DateTime(date.year, date.month);
