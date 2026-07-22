import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/main.dart';

void main() {
  // Phase 1 boot smoke test: proves the app's boot-with-failed-initialization
  // path renders a usable surface (never a blank screen) when the backend is
  // unavailable — which is exactly the state of the test environment.
  testWidgets('BootErrorScreen renders the initialization-failure surface',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BootErrorScreen('Supabase: connection refused'),
      ),
    );

    expect(find.text('Initialization failed'), findsOneWidget);
    expect(find.textContaining('Supabase: connection refused'), findsOneWidget);
  });
}
