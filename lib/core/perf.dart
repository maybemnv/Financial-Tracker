import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Privacy-safe performance instrumentation (Phase 7.7).
///
/// Records *durations and event names only*. No amount, merchant, label, note,
/// account, or message content ever passes through here — the roadmap requires
/// timings without financial values, and the simplest way to guarantee that is
/// an API that cannot carry a payload.
class Perf {
  Perf._();

  static final Map<String, List<int>> _samples = {};

  /// Whether timings are recorded. Off in release so instrumentation never
  /// costs anything in production; flip via `--dart-define=PERF=true`.
  static const bool enabled =
      kDebugMode || bool.fromEnvironment('PERF');

  /// Times an async operation and records the result under [event].
  static Future<T> timeAsync<T>(String event, Future<T> Function() body) async {
    if (!enabled) return body();
    final watch = Stopwatch()..start();
    try {
      return await body();
    } finally {
      watch.stop();
      record(event, watch.elapsedMilliseconds);
    }
  }

  /// Times a synchronous operation.
  static T time<T>(String event, T Function() body) {
    if (!enabled) return body();
    final watch = Stopwatch()..start();
    try {
      return body();
    } finally {
      watch.stop();
      record(event, watch.elapsedMilliseconds);
    }
  }

  static void record(String event, int milliseconds) {
    if (!enabled) return;
    (_samples[event] ??= <int>[]).add(milliseconds);
    developer.log('$event: ${milliseconds}ms', name: 'perf');
  }

  /// p95 for an event, or null when there are no samples. The roadmap's
  /// targets are stated as p95 (Briefing aggregate below 500 ms), so the
  /// summary reports the same statistic rather than a mean that hides tails.
  static int? p95(String event) {
    final samples = _samples[event];
    if (samples == null || samples.isEmpty) return null;
    final sorted = [...samples]..sort();
    final index = ((sorted.length - 1) * 0.95).round();
    return sorted[index];
  }

  static int? median(String event) {
    final samples = _samples[event];
    if (samples == null || samples.isEmpty) return null;
    final sorted = [...samples]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// Snapshot of every recorded event: count, median, p95.
  static Map<String, ({int count, int median, int p95})> summary() => {
        for (final entry in _samples.entries)
          if (entry.value.isNotEmpty)
            entry.key: (
              count: entry.value.length,
              median: median(entry.key)!,
              p95: p95(entry.key)!,
            ),
      };

  @visibleForTesting
  static void reset() => _samples.clear();
}
