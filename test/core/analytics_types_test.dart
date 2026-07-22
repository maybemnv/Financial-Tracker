import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/core/analytics_types.dart';

/// Phase 8.9 — the typed analytics contracts. SQL-side reconciliation lives in
/// `supabase/tests/analytics_reconciliation.sql`.
void main() {
  group('period resolution', () {
    test('12M is the default window', () {
      expect(AnalyticsPeriod.defaultPeriod, AnalyticsPeriod.twelveMonths);
      expect(const AnalyticsQuery().period, AnalyticsPeriod.twelveMonths);
    });

    test('fixed windows ignore the current date', () {
      final jan = DateTime(2026, 1, 15);
      final dec = DateTime(2026, 12, 15);
      for (final p in [
        AnalyticsPeriod.oneMonth,
        AnalyticsPeriod.threeMonths,
        AnalyticsPeriod.sixMonths,
        AnalyticsPeriod.twelveMonths,
      ]) {
        expect(p.monthsAsOf(jan), p.monthsAsOf(dec));
      }
    });

    test('YTD resolves against the current month, not a stored value', () {
      expect(AnalyticsPeriod.yearToDate.monthsAsOf(DateTime(2026, 1, 5)), 1,
          reason: 'In January, year-to-date is one month.');
      expect(AnalyticsPeriod.yearToDate.monthsAsOf(DateTime(2026, 7, 23)), 7);
      expect(AnalyticsPeriod.yearToDate.monthsAsOf(DateTime(2026, 12, 31)), 12);
    });

    test('query equality covers the family toggle', () {
      expect(const AnalyticsQuery(), const AnalyticsQuery());
      expect(const AnalyticsQuery(),
          isNot(const AnalyticsQuery(includeFamilySupport: true)));
    });
  });

  group('top-seven plus Other', () {
    List<LabelSpend> spends(List<double> amounts) => [
          for (var i = 0; i < amounts.length; i++)
            LabelSpend(name: 'L$i', amount: amounts[i]),
        ];

    test('short lists are returned untouched', () {
      final input = spends([5, 4, 3]);
      expect(LabelSpend.topWithOther(input).length, 3);
      expect(LabelSpend.topWithOther(input).map((s) => s.name),
          ['L0', 'L1', 'L2']);
    });

    test('the fold conserves the total exactly', () {
      final input = spends([100, 90, 80, 70, 60, 50, 40, 30, 20, 10]);
      final folded = LabelSpend.topWithOther(input);
      final before = input.fold<double>(0, (s, e) => s + e.amount);
      final after = folded.fold<double>(0, (s, e) => s + e.amount);

      expect(folded.length, 8, reason: 'seven labels plus Other');
      expect(after, before,
          reason: 'Top-N plus Other must equal the ungrouped total, or the '
              'chart disagrees with the ledger.');
      expect(folded.last.name, 'Other');
      expect(folded.last.amount, 30 + 20 + 10);
      expect(folded.last.bucket, SpendBucket.other);
    });

    test('exactly eight folds the smallest into Other', () {
      final folded = LabelSpend.topWithOther(spends([8, 7, 6, 5, 4, 3, 2, 1]));
      expect(folded.length, 8);
      expect(folded.last.amount, 1);
    });

    test('a zero tail adds no empty Other slice', () {
      final folded = LabelSpend.topWithOther(spends([5, 4, 3, 2, 1, 1, 1, 0]));
      expect(folded.map((s) => s.name), isNot(contains('Other')));
    });
  });

  group('bundle parsing', () {
    Map<String, dynamic> envelope(Map<String, dynamic> overrides) => {
          'version': 1,
          'cash_flow': const [],
          'by_label': const [],
          'daily_spend': const [],
          'net_worth': const [],
          'net_worth_current': 0,
          'top_merchants': const [],
          'include_family': false,
          ...overrides,
        };

    test('an unknown version is rejected', () {
      expect(
        () => AnalyticsBundle.fromRpc(envelope({'version': 99})),
        throwsA(isA<FormatException>()),
      );
    });

    test('the current month is flagged partial', () {
      final bundle = AnalyticsBundle.fromRpc(envelope({
        'cash_flow': [
          {
            'year': 2026,
            'month': 7,
            'income': 100,
            'outflow': 40,
            'family_support': 10,
            'is_partial': true,
          }
        ],
      }));
      final point = bundle.cashFlow.single;
      expect(point.isPartial, isTrue,
          reason: 'A partial month must be marked, or a short bar reads as a '
              'real drop in spending.');
      expect(point.personalSpend, 30);
      expect(point.net, 60);
    });

    test('the current month line stops at today, it does not flatten', () {
      final bundle = AnalyticsBundle.fromRpc(
        envelope({
          'daily_spend': [
            {'day': 1, 'current': 10, 'previous': 5},
            {'day': 2, 'current': 20, 'previous': 9},
            {'day': 3, 'current': 0, 'previous': 14},
          ],
        }),
        now: DateTime(2026, 7, 2),
      );
      expect(bundle.dailySpend[0].current, 10);
      expect(bundle.dailySpend[1].current, 20);
      expect(bundle.dailySpend[2].current, isNull,
          reason: 'Days after today have no value; drawing 0 would imply the '
              'month ended with no further spend.');
      expect(bundle.dailySpend[2].previous, 14,
          reason: 'The comparison month is complete and keeps its values.');
    });

    test('untrustworthy net worth points are null, never interpolated', () {
      final bundle = AnalyticsBundle.fromRpc(envelope({
        'net_worth': [
          {'year': 2026, 'month': 5, 'value': null, 'available': false},
          {'year': 2026, 'month': 6, 'value': 1000, 'available': true},
        ],
      }));
      expect(bundle.netWorth[0].available, isFalse);
      expect(bundle.netWorth[0].value, isNull,
          reason: 'A snapshot on the pre-00018 unbounded basis may include '
              'transactions from after the month it claims to describe.');
      expect(bundle.netWorth[1].value, 1000);
    });

    test('review buckets are distinguished from real labels', () {
      final bundle = AnalyticsBundle.fromRpc(envelope({
        'by_label': [
          {'label_id': 'a', 'name': 'Food', 'amount': 100, 'bucket': 'label'},
          {'label_id': null, 'name': 'Unlabeled', 'amount': 50, 'bucket': 'unlabeled'},
          {
            'label_id': null,
            'name': 'Needs primary label',
            'amount': 25,
            'bucket': 'needs_primary'
          },
        ],
      }));
      expect(bundle.byLabel[0].bucket, SpendBucket.label);
      expect(bundle.byLabel[1].bucket, SpendBucket.unlabeled);
      expect(bundle.byLabel[2].bucket, SpendBucket.needsPrimary);
      expect(bundle.totalLabelledSpend, 175);
    });
  });
}
