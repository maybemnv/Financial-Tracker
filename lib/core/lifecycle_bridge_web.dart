import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'lifecycle_bridge.dart';

/// Web implementation of the resume handshake. Talks to
/// `web/flutter_bootstrap.js` over versioned `CustomEvent`s.
class _WebBridge implements LifecycleBridge {
  Future<void> Function()? _handler;
  JSFunction? _resumeListener;
  bool _handling = false;

  @override
  void signalReady() {
    _dispatch('md-dart-ready', {'protocol': LifecycleBridge.protocolVersion});
  }

  @override
  void onResume(Future<void> Function() handler) {
    _handler = handler;
    _resumeListener = ((web.Event event) {
      final detail = (event as web.CustomEvent).detail;
      final attemptId = _readString(detail, 'attemptId');
      if (attemptId != null) _handleResume(attemptId);
    }).toJS;
    web.window.addEventListener('md-resume-request', _resumeListener);
  }

  Future<void> _handleResume(String attemptId) async {
    // Ack on the next rendered frame, BEFORE revalidating. A painted frame is
    // the whole proof the watchdog needs: it exists to catch a dead or blank
    // shell, not a slow one. Acking after `_handler` meant a single slow RPC
    // inside it blew the 3s budget and reloaded a perfectly healthy app,
    // discarding the tab the owner was on.
    afterNextFrame(() {
      _dispatch('md-resume-ack', {
        'protocol': LifecycleBridge.protocolVersion,
        'attemptId': attemptId,
      });
    });

    // Revalidation continues in the background. The JS side suppresses
    // duplicate signals per attempt; this guards against a slow revalidation
    // overlapping a fresh request.
    if (_handling) return;
    _handling = true;
    try {
      await _handler?.call();
    } catch (_) {
      // A failed refresh is not the blank-screen case the watchdog is there to
      // catch: the app is alive and showing its own error/stale state.
    } finally {
      _handling = false;
    }
  }

  void _dispatch(String name, Map<String, Object?> detail) {
    final init = web.CustomEventInit(detail: detail.jsify());
    web.window.dispatchEvent(web.CustomEvent(name, init));
  }

  String? _readString(JSAny? detail, String key) {
    if (detail == null) return null;
    final value = (detail as JSObject)[key];
    return value.isA<JSString>() ? (value as JSString).toDart : null;
  }

  @override
  void dispose() {
    if (_resumeListener != null) {
      web.window.removeEventListener('md-resume-request', _resumeListener);
    }
  }
}

LifecycleBridge createLifecycleBridge() => _WebBridge();
