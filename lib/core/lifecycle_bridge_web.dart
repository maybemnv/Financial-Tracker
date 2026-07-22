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
    // The JS side already suppresses duplicate signals per attempt; this guards
    // against a slow revalidation overlapping a fresh request.
    if (_handling) return;
    _handling = true;
    try {
      await _handler?.call();
    } catch (_) {
      // A failed refresh still acks: the app is alive and showing its own
      // error/stale state, which is not the blank-screen case the watchdog is
      // there to catch. Reloading would throw away that state.
    } finally {
      // Ack only after the next frame actually renders — proof of life.
      afterNextFrame(() {
        _dispatch('md-resume-ack', {
          'protocol': LifecycleBridge.protocolVersion,
          'attemptId': attemptId,
        });
        _handling = false;
      });
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
