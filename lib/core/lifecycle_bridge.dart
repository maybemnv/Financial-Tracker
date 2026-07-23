import 'package:flutter/widgets.dart';

import 'lifecycle_bridge_stub.dart'
    if (dart.library.js_interop) 'lifecycle_bridge_web.dart';

/// The JS <-> Dart resume handshake (Phase 11.3). On web this is backed by
/// browser events; everywhere else it is a no-op, so the app compiles and runs
/// unchanged off the web.
///
/// Contract, versioned by [protocolVersion]:
///   Dart -> JS  `md-dart-ready`   once the first usable frame has painted
///   JS  -> Dart `md-resume-request` on foreground / bfcache / WebGL loss
///   Dart -> JS  `md-resume-ack`    after the next frame renders
///
/// The ack reports liveness only. It fires on the next rendered frame and does
/// not wait for revalidation to finish, so a slow network can never be mistaken
/// for a dead shell.
///
/// The JS watchdog reloads once if an ack does not arrive in time, then stops;
/// see `web/flutter_bootstrap.js`.
abstract class LifecycleBridge {
  static const int protocolVersion = 1;

  /// Announce that Dart has initialized and painted. Call after the first
  /// frame, never before — the JS side hides the boot surface on this signal.
  void signalReady();

  /// Register the callback that revalidates app state on resume. It runs in the
  /// background and its duration does not gate the ack, so it is free to do
  /// network work without risking a watchdog reload.
  void onResume(Future<void> Function() handler);

  void dispose();

  static LifecycleBridge create() => createLifecycleBridge();
}

/// Waits for the next rendered frame, then runs [after]. Used to ack only once
/// a real frame exists, which is what proves the app is actually alive.
void afterNextFrame(VoidCallback after) {
  WidgetsBinding.instance.addPostFrameCallback((_) => after());
}
