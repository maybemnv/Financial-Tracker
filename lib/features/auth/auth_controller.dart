import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';

/// Typed owner-auth lifecycle states (Phase 2.6). Kept distinct from Supabase's
/// own `AuthState` to model the *owner* gate, not just "has a session".
enum OwnerAuthStatus {
  /// Restoring a persisted session before any finance provider is built.
  initializing,

  /// No session — show the sign-in screen.
  signedOut,

  /// An OAuth / magic-link redirect is being exchanged for a session.
  processingCallback,

  /// Signed in and confirmed to be the registered owner.
  authenticatedOwner,

  /// Signed in but not the registered owner — fail closed.
  authenticatedNonOwner,

  /// Recoverable error (network, config); the user can retry.
  error,
}

class OwnerAuthState {
  const OwnerAuthState(this.status, {this.message});

  final OwnerAuthStatus status;
  final String? message;

  bool get isOwner => status == OwnerAuthStatus.authenticatedOwner;

  OwnerAuthState copyWith({OwnerAuthStatus? status, String? message}) =>
      OwnerAuthState(status ?? this.status, message: message);
}

class AuthController extends StateNotifier<OwnerAuthState> {
  AuthController({SupabaseClient? client})
      : _client = client ?? SupabaseService().client,
        super(const OwnerAuthState(OwnerAuthStatus.initializing)) {
    _bootstrap();
  }

  final SupabaseClient _client;
  StreamSubscription<AuthState>? _sub;

  GoTrueClient get _auth => _client.auth;

  void _bootstrap() {
    // React to every session change (initial, refresh, callback, sign-out).
    _sub = _auth.onAuthStateChange.listen(_onAuthChange, onError: (Object e) {
      state = OwnerAuthState(OwnerAuthStatus.error, message: e.toString());
    });

    // Restore any persisted browser session synchronously.
    final session = _auth.currentSession;
    if (session != null) {
      unawaited(_resolveOwner());
    } else {
      state = const OwnerAuthState(OwnerAuthStatus.signedOut);
    }
  }

  Future<void> _onAuthChange(AuthState data) async {
    switch (data.event) {
      case AuthChangeEvent.initialSession:
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
        if (data.session != null) {
          await _resolveOwner();
        } else {
          state = const OwnerAuthState(OwnerAuthStatus.signedOut);
        }
        break;
      case AuthChangeEvent.signedOut:
      case AuthChangeEvent.passwordRecovery:
        state = const OwnerAuthState(OwnerAuthStatus.signedOut);
        break;
      default:
        break;
    }
  }

  /// Verifies the signed-in user is the registered owner via `app_is_owner()`.
  /// Transitional: before the Phase 2 migrations exist the RPC is absent — a
  /// missing function is treated as owner so the app is usable during rollout.
  /// A present-but-false result fails closed to non-owner.
  Future<void> _resolveOwner() async {
    try {
      final result = await _client.rpc('app_is_owner');
      final isOwner = result == true;
      state = OwnerAuthState(isOwner
          ? OwnerAuthStatus.authenticatedOwner
          : OwnerAuthStatus.authenticatedNonOwner);
    } on PostgrestException catch (e) {
      // 42883 / PGRST202: function not found — pre-migration transitional path.
      if (e.code == '42883' || e.code == 'PGRST202') {
        state = const OwnerAuthState(OwnerAuthStatus.authenticatedOwner);
      } else {
        state = OwnerAuthState(OwnerAuthStatus.error, message: e.message);
      }
    } catch (e) {
      state = OwnerAuthState(OwnerAuthStatus.error, message: e.toString());
    }
  }

  /// Re-check owner status (used on resume after a token refresh).
  Future<void> refreshOwner() async {
    if (_auth.currentSession != null) {
      await _resolveOwner();
    }
  }

  Future<void> signInWithGoogle() async {
    state = const OwnerAuthState(OwnerAuthStatus.processingCallback);
    try {
      await _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _redirectUrl(),
      );
      // The browser redirects; the callback re-enters via onAuthStateChange.
    } catch (e) {
      state = OwnerAuthState(OwnerAuthStatus.error, message: e.toString());
    }
  }

  Future<void> sendMagicLink(String email) async {
    await _auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: _redirectUrl(),
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
    state = const OwnerAuthState(OwnerAuthStatus.signedOut);
  }

  /// Post-auth redirect target. On web this is the app's own origin so the
  /// callback lands back in the SPA. Null lets supabase_flutter pick the
  /// platform default on non-web builds.
  ///
  /// `Uri.origin` throws unless the scheme is http/https and a host is present,
  /// so the non-web `file:` base is screened out before it is read rather than
  /// after — a thrown StateError here would escape `sendMagicLink`, which has
  /// no catch of its own.
  String? _redirectUrl() {
    if (!kIsWeb) return null;
    final base = Uri.base;
    if (base.host.isEmpty) return null;
    if (base.scheme != 'http' && base.scheme != 'https') return null;
    return base.origin;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, OwnerAuthState>(
  (ref) => AuthController(),
);
