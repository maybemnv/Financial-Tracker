import 'package:finance_tracker/core/dashboard_analytics.dart';
import 'package:finance_tracker/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardAnalytics.fromTransactions', () {
    test('separates income spending and investments in the current month', () {
      final analytics = DashboardAnalytics.fromTransactions(
        [
          Transaction(
            amount: 5000,
            type: 'credit',
            direction: 'inflow',
            createdAt: DateTime(2026, 7, 2),
          ),
          Transaction(
            amount: 1200,
            type: 'debit',
            direction: 'outflow',
            category: 'Food',
            createdAt: DateTime(2026, 7, 3),
          ),
          Transaction(
            amount: 800,
            type: 'investment',
            direction: 'outflow',
            createdAt: DateTime(2026, 7, 4),
          ),
          Transaction(
            amount: 400,
            type: 'transfer',
            direction: 'outflow',
            createdAt: DateTime(2026, 7, 5),
          ),
        ],
        now: DateTime(2026, 7, 10),
      );

      expect(analytics.currentMonth.income, 5000);
      expect(analytics.currentMonth.spending, 1200);
      expect(analytics.currentMonth.investments, 800);
      expect(analytics.currentMonth.savings, 3800);
      expect(analytics.currentMonth.savingsRate, closeTo(76, 0.01));
      expect(analytics.spendingCategories.single.label, 'Food');
      expect(analytics.spendingCategories.single.amount, 1200);
    });

    test(
        'uses transactedAt for month bucketing and exposes uncategorized spend',
        () {
      final analytics = DashboardAnalytics.fromTransactions(
        [
          Transaction(
            amount: 700,
            type: 'debit',
            direction: 'outflow',
            createdAt: DateTime(2026, 7, 1),
            transactedAt: DateTime(2026, 6, 30),
          ),
          Transaction(
            amount: 900,
            type: 'debit',
            direction: 'outflow',
            createdAt: DateTime(2026, 7, 2),
          ),
        ],
        now: DateTime(2026, 7, 10),
      );

      expect(analytics.currentMonth.spending, 900);
      expect(analytics.currentMonth.uncategorizedCount, 1);
      expect(
        analytics.monthlyTrend.last.spending,
        900,
        reason: 'July trend should exclude the backdated June transaction.',
      );
      expect(
        analytics.monthlyTrend[analytics.monthlyTrend.length - 2].spending,
        700,
        reason:
            'June trend should include the transaction because transactedAt is in June.',
      );
      expect(analytics.spendingCategories.single.label, 'Uncategorized');
    });

    test('can focus a prior month and counts PayPal payout inflows as income',
        () {
      final analytics = DashboardAnalytics.fromTransactions(
        [
          Transaction(
            amount: 30219.77,
            type: 'credit',
            direction: 'inflow',
            merchant: 'PayPal',
            note: 'PayPal payout NEFTINW-1635580463',
            transactedAt: DateTime(2026, 7, 1),
          ),
          Transaction(
            amount: 26165.94,
            type: 'credit',
            direction: 'inflow',
            merchant: 'PayPal',
            note: 'PayPal payout NEFTINW-1619160089',
            transactedAt: DateTime(2026, 6, 15),
          ),
          Transaction(
            amount: 1200,
            type: 'debit',
            direction: 'outflow',
            category: 'Food',
            transactedAt: DateTime(2026, 6, 20),
          ),
        ],
        now: DateTime(2026, 7, 5),
        focusMonth: DateTime(2026, 6),
      );

      expect(analytics.currentMonth.month, DateTime(2026, 6));
      expect(analytics.currentMonth.income, 26165.94);
      expect(analytics.currentMonth.spending, 1200);
      expect(analytics.currentMonth.savings, 24965.94);
      expect(
        analytics.availableMonths,
        [DateTime(2026, 7), DateTime(2026, 6)],
      );
    });
  });
}
