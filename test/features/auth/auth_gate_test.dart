import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:finance_tracker/features/auth/auth_controller.dart';
import 'package:finance_tracker/features/auth/auth_gate.dart';

void main() {
  // A bare SupabaseClient never connects until a request is made, so we can
  // drive the real signed-out bootstrap path without any backend.
  AuthController buildController() => AuthController(
        client: SupabaseClient(
          'http://localhost:54321',
          'test-anon-key',
          // No auto-refresh timer, so the widget tester has no pending timers.
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  testWidgets('gate shows the sign-in screen when there is no session',
      (tester) async {
    final controller = buildController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await tester.pump();

    expect(controller.state.status, OwnerAuthStatus.signedOut);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Send magic link'), findsOneWidget);
  });

  test('bare controller resolves to signedOut without a session', () async {
    final controller = buildController();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.isOwner, isFalse);
    expect(controller.state.status, OwnerAuthStatus.signedOut);
  });
}
