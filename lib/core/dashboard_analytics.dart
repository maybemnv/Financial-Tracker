import '../models/transaction.dart';

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
    var monthInvestments = 0.0;
    var monthUncategorized = 0;
    final categoryTotals = <String, double>{};
    final dailyTotals = <DateTime, _DailyAccumulator>{};

    for (final transaction in currentMonthTransactions) {
      final effectiveDate = transaction.effectiveDate;
      final dayKey = DateTime(
        effectiveDate.year,
        effectiveDate.month,
        effectiveDate.day,
      );
      final daily = dailyTotals.putIfAbsent(dayKey, _DailyAccumulator.new);

      if (_isIncome(transaction)) {
        monthIncome += transaction.amount;
        daily.income += transaction.amount;
      } else if (_isSpending(transaction)) {
        monthSpending += transaction.amount;
        daily.spending += transaction.amount;

        final category = _categoryLabel(transaction);
        categoryTotals.update(
          category,
          (value) => value + transaction.amount,
          ifAbsent: () => transaction.amount,
        );
        if (category == 'Uncategorized') {
          monthUncategorized += 1;
        }
      } else if (_isInvestmentOutflow(transaction)) {
        monthInvestments += transaction.amount;
      }
    }

    final spendingCategories = categoryTotals.entries
        .map(
          (entry) => DashboardCategoryPoint(
            label: entry.key,
            amount: entry.value,
            share: monthSpending == 0 ? 0 : entry.value / monthSpending,
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

      if (_isIncome(transaction)) {
        bucket.income += transaction.amount;
      } else if (_isSpending(transaction)) {
        bucket.spending += transaction.amount;
      } else if (_isInvestmentOutflow(transaction)) {
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
          .where((transaction) => _isSpending(transaction))
          .where(
              (transaction) => _categoryLabel(transaction) == 'Uncategorized')
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
  });

  final DateTime month;
  final double income;
  final double spending;
  final double investments;
  final double savings;
  final double savingsRate;
  final int transactionCount;
  final int uncategorizedCount;
  final double averageDailySpending;
  final double projectedSpending;

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
  });

  final String label;
  final double amount;
  final double share;
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

bool _isIncome(Transaction transaction) {
  if (transaction.isTransfer || transaction.isInvestment) return false;
  return transaction.type == 'credit' || transaction.isInflow;
}

bool _isSpending(Transaction transaction) {
  if (transaction.isTransfer || transaction.isInvestment) return false;
  return transaction.type == 'debit' || transaction.isOutflow;
}

bool _isInvestmentOutflow(Transaction transaction) =>
    transaction.isInvestment && transaction.isOutflow;

String _categoryLabel(Transaction transaction) {
  final category = transaction.category?.trim();
  if (category == null || category.isEmpty) {
    return 'Uncategorized';
  }
  return category;
}

int _daysInMonth(DateTime date) => DateTime(date.year, date.month + 1, 0).day;

DateTime _monthStart(DateTime date) => DateTime(date.year, date.month);
