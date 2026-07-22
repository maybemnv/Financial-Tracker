import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/features/transactions/transaction_list_screen.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/transaction.dart';
import 'package:finance_tracker/models/transaction_label.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/label_provider.dart';

class _TestAccountNotifier extends AccountNotifier {
  _TestAccountNotifier() {
    state = AsyncValue.data([
      Account(id: 'cash', name: 'Cash', type: 'cash'),
    ]);
  }

  @override
  Future<void> load() async {}

  @override
  void subscribe() {}

  @override
  void unsubscribe() {}
}

class _TestLabelNotifier extends LabelNotifier {
  _TestLabelNotifier() {
    state = const AsyncValue.data([
      TransactionLabel(id: 'food', name: 'Food', color: '#1D76DB'),
    ]);
  }

  @override
  Future<void> load() async {}

  @override
  void subscribe() {}

  @override
  void unsubscribe() {}
}

void main() {
  testWidgets('AddTransactionScreen date/time picker updates the date label',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith((ref) => _TestAccountNotifier()),
          labelProvider.overrideWith((ref) => _TestLabelNotifier()),
        ],
        child: const MaterialApp(
          home: AddTransactionScreen(),
        ),
      ),
    );

    expect(find.text('Now (tap to set)'), findsOneWidget,
        reason:
            'The transaction date label should default to Now before user selection.');

    await tester.tap(find.text('Now (tap to set)'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget,
        reason: 'Tapping the date row should open the date picker first.');

    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget,
        reason:
            'Confirming the date should open the time picker before updating transactedAt.');

    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();

    expect(find.text('Now (tap to set)'), findsNothing,
        reason:
            'After confirming date and time, the label must no longer indicate a null transactedAt value.');
    expect(find.textContaining('Today,'), findsOneWidget,
        reason:
            'Selecting today should render a concrete Today, HH:mm transaction timestamp.');
  });

  testWidgets('pre-fills an older transaction for editing and keeps its labels',
      (tester) async {
    // The form body is a lazy ListView; a tall surface lets the whole form
    // build so mid/bottom fields are present without scroll gymnastics.
    await tester.binding.setSurfaceSize(const Size(600, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith((ref) => _TestAccountNotifier()),
          labelProvider.overrideWith((ref) => _TestLabelNotifier()),
        ],
        child: MaterialApp(
          home: AddTransactionScreen(
            transaction: Transaction(
              id: 'old-transaction',
              amount: 1000,
              type: 'debit',
              accountId: 'cash',
              merchant: 'Corner Cafe',
              bank: 'Cash',
              labels: const [
                TransactionLabel(id: 'food', name: 'Food', color: '#1D76DB'),
              ],
              transactedAt: DateTime(2026, 7, 8, 12, 30),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Edit Transaction'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('FOOD'), findsOneWidget);
    // Assert the merchant field's editing value through its EditableText —
    // `find.byDisplayValue` is not part of Flutter's CommonFinders and was the
    // D7 test-gate breakage.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is EditableText && widget.controller.text == 'Corner Cafe',
      ),
      findsOneWidget,
      reason: 'The merchant field should be pre-filled for editing.',
    );
  });
}
