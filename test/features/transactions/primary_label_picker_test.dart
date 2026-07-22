import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/features/transactions/transaction_list_screen.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/transaction.dart';
import 'package:finance_tracker/models/transaction_label.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/label_provider.dart';

/// Phase 5.5 — the primary-label picker. An expense's full amount attributes
/// to exactly one label (PRD §4, D3); `save_transaction_with_labels` rejects a
/// labelled expense that has not named one, so the form must always be able to
/// produce a valid primary before it submits.
class _TestAccountNotifier extends AccountNotifier {
  _TestAccountNotifier() {
    state = AsyncValue.data([Account(id: 'cash', name: 'Cash', type: 'cash')]);
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
      TransactionLabel(id: 'travel', name: 'Travel', color: '#B5472F'),
      TransactionLabel(
        id: 'family',
        name: 'Family',
        color: '#2D6A4F',
        excludeFromPersonalSpend: true,
      ),
    ]);
  }

  @override
  Future<void> load() async {}
  @override
  void subscribe() {}
  @override
  void unsubscribe() {}
}

Future<void> _pumpForm(WidgetTester tester, {Transaction? transaction}) async {
  await tester.binding.setSurfaceSize(const Size(600, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountProvider.overrideWith((ref) => _TestAccountNotifier()),
        labelProvider.overrideWith((ref) => _TestLabelNotifier()),
      ],
      child: MaterialApp(home: AddTransactionScreen(transaction: transaction)),
    ),
  );
  await tester.pumpAndSettle();
}

/// The picker renders selected labels as ChoiceChips under "Counts under".
bool _primaryChipSelected(WidgetTester tester, String name) {
  final chip = tester.widget<ChoiceChip>(
    find.ancestor(
      of: find.text(name),
      matching: find.byType(ChoiceChip),
    ),
  );
  return chip.selected;
}

void main() {
  testWidgets('no picker until an expense has labels', (tester) async {
    await _pumpForm(tester);
    expect(find.text('Counts under'), findsNothing,
        reason: 'An unlabelled expense reports as Unlabeled and needs no '
            'primary, so the picker must stay out of the way.');
  });

  testWidgets('a single label becomes primary without an extra tap',
      (tester) async {
    await _pumpForm(tester);

    await tester.tap(find.text('FOOD'));
    await tester.pumpAndSettle();

    expect(find.text('Counts under'), findsOneWidget);
    expect(_primaryChipSelected(tester, 'Food'), isTrue,
        reason: 'With one candidate there is nothing to disambiguate, so the '
            'common case must not require a second tap.');
    expect(find.text('Choose one to save.'), findsNothing);
  });

  testWidgets('a second label forces an explicit choice', (tester) async {
    await _pumpForm(tester);

    await tester.tap(find.text('FOOD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TRAVEL'));
    await tester.pumpAndSettle();

    // The auto-chosen primary survives; the amount still attributes once.
    expect(_primaryChipSelected(tester, 'Food'), isTrue);
    expect(_primaryChipSelected(tester, 'Travel'), isFalse);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Travel'));
    await tester.pumpAndSettle();

    expect(_primaryChipSelected(tester, 'Travel'), isTrue);
    expect(_primaryChipSelected(tester, 'Food'), isFalse,
        reason: 'Exactly one label may be primary — picking Travel must clear '
            'Food, never leave the amount attributable twice.');
  });

  testWidgets('deselecting the primary label clears it', (tester) async {
    await _pumpForm(tester);

    // Three labels, so removing the primary still leaves an ambiguous choice
    // rather than collapsing to the single-candidate auto-select.
    for (final name in ['FOOD', 'TRAVEL', 'FAMILY']) {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }
    expect(_primaryChipSelected(tester, 'Food'), isTrue);

    // Remove Food, the current primary, from the selection entirely.
    await tester.tap(find.text('FOOD'));
    await tester.pumpAndSettle();

    expect(find.text('Choose one to save.'), findsOneWidget,
        reason: 'Dropping the primary label must surface the unresolved state '
            'rather than silently leaving a stale primary_label_id.');
    expect(_primaryChipSelected(tester, 'Travel'), isFalse);
    expect(_primaryChipSelected(tester, 'Family'), isFalse);
  });

  testWidgets('dropping to one remaining label re-arms it as primary',
      (tester) async {
    await _pumpForm(tester);

    for (final name in ['FOOD', 'TRAVEL', 'FAMILY']) {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(ChoiceChip, 'Travel'));
    await tester.pumpAndSettle();
    expect(_primaryChipSelected(tester, 'Travel'), isTrue);

    // Remove the other two; one candidate remains.
    await tester.tap(find.text('FOOD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAMILY'));
    await tester.pumpAndSettle();

    expect(_primaryChipSelected(tester, 'Travel'), isTrue);
    expect(find.text('Choose one to save.'), findsNothing);
  });

  testWidgets('credits never show the picker', (tester) async {
    await _pumpForm(tester);

    await tester.tap(find.text('Credit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FOOD'));
    await tester.pumpAndSettle();

    expect(find.text('Counts under'), findsNothing,
        reason: 'Only expenses attribute to a primary label; income carries '
            'labels for context only.');
  });

  testWidgets('editing restores the stored primary, not the first label',
      (tester) async {
    await _pumpForm(
      tester,
      transaction: Transaction(
        id: 'existing',
        amount: 500,
        type: 'debit',
        accountId: 'cash',
        // Travel is primary even though Food is attached first — resolution is
        // by id, never by relation order.
        primaryLabelId: 'travel',
        labels: const [
          TransactionLabel(id: 'food', name: 'Food', color: '#1D76DB'),
          TransactionLabel(id: 'travel', name: 'Travel', color: '#B5472F'),
        ],
      ),
    );

    expect(_primaryChipSelected(tester, 'Travel'), isTrue);
    expect(_primaryChipSelected(tester, 'Food'), isFalse);
  });
}
