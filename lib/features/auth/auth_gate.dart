import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/theme.dart';
import 'auth_controller.dart';
import 'sign_in_screen.dart';

/// Routes the app by owner-auth state. Finance providers live inside [AppShell],
/// so they are never constructed until the owner gate succeeds (Phase 2.6 /
/// TODO 2.6 "prevent finance providers from loading before the owner gate").
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    switch (auth.status) {
      case OwnerAuthStatus.initializing:
      case OwnerAuthStatus.processingCallback:
        return const _AuthBusy();
      case OwnerAuthStatus.signedOut:
        return const SignInScreen();
      case OwnerAuthStatus.authenticatedNonOwner:
        return const _AccessDenied();
      case OwnerAuthStatus.error:
        return _AuthError(message: auth.message);
      case OwnerAuthStatus.authenticatedOwner:
        return const AppShell();
    }
  }
}

class _AuthBusy extends StatelessWidget {
  const _AuthBusy();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.scaffold,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _AccessDenied extends ConsumerWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(24),
              decoration:
                  AppTheme.panelDecoration(color: AppTheme.paper, accentTop: true),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Access denied', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  Text(
                    'This account is signed in but is not the registered owner '
                    'of this finance desk. No financial data is accessible.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthError extends ConsumerWidget {
  const _AuthError({this.message});

  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(24),
              decoration:
                  AppTheme.panelDecoration(color: AppTheme.paper, accentTop: true),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sign-in problem', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  Text(
                    message ?? 'Something went wrong while checking access.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => ref
                            .read(authControllerProvider.notifier)
                            .refreshOwner(),
                        child: const Text('Retry'),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () =>
                            ref.read(authControllerProvider.notifier).signOut(),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
