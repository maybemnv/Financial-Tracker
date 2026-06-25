import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device currently has any network connection. Drives the offline
/// banner shown across the app. `connectivity_plus` works on Android + Windows.
final connectivityProvider = StreamProvider<bool>((ref) async {
  final connectivity = Connectivity();
  final controller = StreamController<bool>.broadcast();

  bool isOnline(List<ConnectivityResult> r) =>
      r.isNotEmpty && r.any((x) => x != ConnectivityResult.none);

  // Emit the current state immediately, then subsequent changes.
  final initial = await connectivity.checkConnectivity();
  controller.add(isOnline(initial));
  controller.addStream(connectivity.onConnectivityChanged.map(isOnline));
  return controller.stream;
});
