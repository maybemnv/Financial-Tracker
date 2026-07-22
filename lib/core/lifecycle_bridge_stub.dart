import 'lifecycle_bridge.dart';

/// Non-web fallback: the resume handshake is a browser concept, so off the web
/// every call is a no-op and the app behaves exactly as before.
class _NoopBridge implements LifecycleBridge {
  @override
  void signalReady() {}

  @override
  void onResume(Future<void> Function() handler) {}

  @override
  void dispose() {}
}

LifecycleBridge createLifecycleBridge() => _NoopBridge();
