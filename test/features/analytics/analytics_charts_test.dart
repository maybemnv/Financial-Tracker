import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/core/analytics_types.dart';
import 'package:finance_tracker/features/analytics/analytics_charts.dart';

/// Phase 8.9 — chart widget coverage: empty, populated, single-point, and the
/// table alternative, all at a 360-pixel viewport.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(360, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('cash flow', () {
    test('components never become extra bars', () {
      // Personal Spend + Family Support == Outflow. If they were drawn as
      // their own bars a reader could add them to Outflow and double-count.
      const p = CashFlowPoint(
        year: 2026,
        month: 7,
        income: 1000,
        outflow: 600,
        familySupport: 200,
        isPartial: false,
      );
      expect(p.personalSpend + p.familySupport, p.outflow);
      expect(p.net, 400);
    });

    testWidgets('empty period renders a message, not an axis', (tester) async {
      await _pump(tester, const CashFlowChart(points: []));
      expect(find.text('No cash flow in this period.'), findsOneWidget);
    });

    testWidgets('a partial month is called out in words', (tester) async {
      await _pump(
        tester,
        const CashFlowChart(points: [
          CashFlowPoint(
            year: 2026,
            month: 7,
            income: 100,
            outflow: 60,
            familySupport: 0,
            isPartial: true,
          ),
        ]),
      );
      expect(find.textContaining('still in progress'), findsOneWidget,
          reason: 'Opacity alone cannot carry this — a short bar would read '
              'as a real drop in spending.');
    });

    testWidgets('the table alternative shows exact values', (tester) async {
      await _pump(
        tester,
        const CashFlowChart(points: [
          CashFlowPoint(
            year: 2026,
            month: 7,
            income: 1000,
            outflow: 600,
            familySupport: 200,
            isPartial: false,
          ),
        ]),
      );
      await tester.tap(find.text('TABLE'));
      await tester.pumpAndSettle();

      expect(find.text('₹1,000'), findsOneWidget);
      expect(find.text('₹600'), findsOneWidget);
      expect(find.text('₹400'), findsOneWidget, reason: 'net');
    });

    testWidgets('a legend is present for two series', (tester) async {
      await _pump(
        tester,
        const CashFlowChart(points: [
          CashFlowPoint(
            year: 2026,
            month: 7,
            income: 10,
            outflow: 5,
            familySupport: 0,
            isPartial: false,
          ),
        ]),
      );
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Total Outflow'), findsOneWidget);
    });
  });

  group('spending by label', () {
    testWidgets('review buckets are labelled as not-a-category',
        (tester) async {
      await _pump(
        tester,
        const LabelSpendChart(
          includeFamily: false,
          slices: [
            LabelSpend(name: 'Food', amount: 500, labelId: 'food'),
            LabelSpend(
                name: 'Needs primary label',
                amount: 200,
                bucket: SpendBucket.needsPrimary),
          ],
        ),
      );
      expect(find.textContaining('Not a category'), findsOneWidget);
      expect(find.text('₹500'), findsOneWidget,
          reason: 'Direct value labels are the readability channel the '
              'palette requires.');
    });

    testWidgets('the family toggle is stated, not implied', (tester) async {
      await _pump(
        tester,
        const LabelSpendChart(includeFamily: false, slices: []),
      );
      expect(find.textContaining('Family Support is excluded'), findsOneWidget);
    });
  });

  group('daily cumulative', () {
    testWidgets('too little history renders a message', (tester) async {
      await _pump(tester, const DailyCumulativeChart(points: []));
      expect(find.textContaining('Not enough of the month'), findsOneWidget);
    });

    testWidgets('days after today show a dash, never zero', (tester) async {
      await _pump(
        tester,
        const DailyCumulativeChart(points: [
          DailyCumulativePoint(day: 1, current: 100, previous: 50),
          DailyCumulativePoint(day: 2, current: null, previous: 90),
        ]),
      );
      await tester.tap(find.text('TABLE'));
      await tester.pumpAndSettle();
      expect(find.text('—'), findsOneWidget,
          reason: 'Rendering 0 would imply the month finished with no spend.');
    });
  });

  group('net worth', () {
    testWidgets('no snapshots yet renders a message', (tester) async {
      await _pump(tester, const NetWorthChart(points: [], current: 5000));
      expect(find.textContaining('No month-end snapshots yet'), findsOneWidget);
    });

    testWidgets('untrustworthy months are named, not interpolated',
        (tester) async {
      await _pump(
        tester,
        const NetWorthChart(
          current: 5000,
          points: [
            NetWorthPoint(
                year: 2026, month: 5, value: null, available: false),
            NetWorthPoint(
                year: 2026, month: 6, value: 4000, available: true),
          ],
        ),
      );
      expect(find.textContaining('cannot be charted'), findsOneWidget);

      await tester.tap(find.text('TABLE'));
      await tester.pumpAndSettle();
      expect(find.text('unavailable'), findsOneWidget);
      expect(find.text('₹4,000'), findsOneWidget);
      expect(find.text('₹5,000'), findsOneWidget, reason: 'live value');
    });

    testWidgets('a single point still renders', (tester) async {
      await _pump(
        tester,
        const NetWorthChart(
          current: 100,
          points: [
            NetWorthPoint(year: 2026, month: 6, value: 90, available: true),
          ],
        ),
      );
      expect(find.textContaining('Net worth history'), findsOneWidget);
    });
  });
}
