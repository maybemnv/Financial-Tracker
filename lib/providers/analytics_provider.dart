import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics_types.dart';
import '../core/perf.dart';
import '../core/supabase.dart';
import 'ledger_provider.dart';

/// The active analytics selection. Held separately from the data so changing
/// period or the Family toggle does not rebuild anything until the new bundle
/// arrives.
final analyticsQueryProvider =
    StateProvider<AnalyticsQuery>((ref) => const AnalyticsQuery());

/// The four charts and their non-chart companions, from one `get_analytics`
/// call. Nothing here recomputes the ledger client-side.
final analyticsProvider = FutureProvider<AnalyticsBundle>((ref) async {
  final query = ref.watch(analyticsQueryProvider);
  // Refresh when the ledger changes, not on every page scroll.
  ref.watch(ledgerProvider.select((s) => s.rows.length));

  return Perf.timeAsync('analytics_bundle', () async {
    final now = DateTime.now();
    final result = await SupabaseService().client.rpc(
      'get_analytics',
      params: {
        'p_months': query.period.monthsAsOf(now),
        'p_include_family': query.includeFamilySupport,
      },
    );
    return AnalyticsBundle.fromRpc(
      Map<String, dynamic>.from(result as Map),
      now: now,
    );
  });
});
