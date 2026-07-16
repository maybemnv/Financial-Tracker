import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/features/transactions/transaction_list_screen.dart';
import 'package:finance_tracker/models/account.dart';
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
}
