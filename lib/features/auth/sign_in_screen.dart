import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';

/// Focused single-owner sign-in surface: Google OAuth and email magic link,
/// with callback progress, a resend cooldown, and readable errors (Phase 2.6).
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _notice;
  bool _sending = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _cooldown = 45);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _cooldown = _cooldown <= 1 ? 0 : _cooldown - 1);
      if (_cooldown == 0) t.cancel();
    });
  }

  Future<void> _sendLink() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _notice = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).sendMagicLink(
            _emailCtrl.text,
          );
      if (!mounted) return;
      setState(() => _notice =
          'Magic link sent to ${_emailCtrl.text.trim()}. Check your inbox.');
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _notice = 'Could not send link: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final processing = auth.status == OwnerAuthStatus.processingCallback;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.panelDecoration(
                color: AppTheme.paper,
                accentTop: true,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Finance Tracker', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text(
                      'Owner sign-in. This desk holds one person’s finances.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: processing
                          ? null
                          : () => ref
                              .read(authControllerProvider.notifier)
                              .signInWithGoogle(),
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(child: Divider(color: AppTheme.ink)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or', style: theme.textTheme.bodySmall),
                        ),
                        const Expanded(child: Divider(color: AppTheme.ink)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email for a magic link',
                      ),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return 'Enter your email';
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: (_sending || processing || _cooldown > 0)
                          ? null
                          : _sendLink,
                      child: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_cooldown > 0
                              ? 'Resend in ${_cooldown}s'
                              : 'Send magic link'),
                    ),
                    if (processing) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text('Completing sign-in…',
                              style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration:
                            AppTheme.panelDecoration(color: AppTheme.paperAlt),
                        child:
                            Text(_notice!, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                    if (auth.status == OwnerAuthStatus.error &&
                        auth.message != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        auth.message!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppTheme.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
