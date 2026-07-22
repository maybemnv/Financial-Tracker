import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/transaction_label.dart';
import 'package:finance_tracker/providers/label_provider.dart';

/// A test double that drives the same [AsyncValue] state machine as the real
/// [LabelNotifier] without touching Supabase, so the harness can exercise the
/// loading -> data -> error transitions the UI depends on.
class _FakeLabelNotifier extends LabelNotifier {
  _FakeLabelNotifier() : super();

  @override
  Future<void> load() async {
    state = const AsyncValue.loading();
    await Future<void>.delayed(Duration.zero);
    state = const AsyncValue.data([
      TransactionLabel(id: 'food', name: 'Food', color: '#1D76DB'),
    ]);
  }

  @override
  void subscribe() {}

  @override
  void unsubscribe() {}

  void fail(Object error) => state = AsyncValue.error(error, StackTrace.empty);
}

void main() {
  test('label provider transitions loading -> data -> error', () async {
    final notifier = _FakeLabelNotifier();
    final container = ProviderContainer(
      overrides: [labelProvider.overrideWith((ref) => notifier)],
    );
    addTearDown(container.dispose);

    // Starts in the loading state before any data resolves.
    expect(container.read(labelProvider).isLoading, isTrue);

    await notifier.load();
    final loaded = container.read(labelProvider);
    expect(loaded.hasValue, isTrue);
    expect(loaded.value, hasLength(1));
    expect(loaded.value!.single.name, 'Food');

    notifier.fail(StateError('boom'));
    expect(container.read(labelProvider).hasError, isTrue);
  });
}
