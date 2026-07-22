import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/aggregates.dart';
import '../core/ledger_query.dart';
import '../core/perf.dart';
import '../core/supabase.dart';
import '../models/transaction.dart';
import 'ledger_provider.dart';

/// Owner-scoped aggregates (Phase 7.4). Each is one round trip that replaces
/// walking the ledger client-side.

/// Canonical metrics for a month. Defaults to the current month.
final briefingSummaryProvider =
    FutureProvider.family<BriefingSummary, ({int year, int month})?>(
        (ref, period) async {
  // Recompute when the ledger changes; the notifier only emits on real writes
  // and patched Realtime events, not on every scroll page.
  ref.watch(ledgerProvider.select((s) => s.rows.length));

  return Perf.timeAsync('briefing_summary', () async {
    final result = await SupabaseService().client.rpc(
      'get_briefing_summary',
      params: {'p_month': period?.month, 'p_year': period?.year},
    );
    return BriefingSummary.fromRpc(Map<String, dynamic>.from(result as Map));
  });
});

// Account balances live in account_provider.accountBalancesProvider — one
// provider per concept, so no screen has to know which of two to watch.

/// Whole-ledger label usage, keyed by label id.
final labelUsageStatsProvider =
    FutureProvider<Map<String, LabelUsageStat>>((ref) async {
  ref.watch(ledgerProvider.select((s) => s.rows.length));

  final result = await SupabaseService().client.rpc('get_label_usage');
  return LabelUsageStat.mapFromRpc(Map<String, dynamic>.from(result as Map));
});

/// One page of a review bucket, fetched server-side.
///
/// The review queue is no longer derived from loaded rows: with paging, the
/// unresolved rows the owner needs to fix are usually the *old* ones, which are
/// exactly the rows a first page does not contain.
final reviewBucketProvider =
    FutureProvider.family<List<Transaction>, UnresolvedFilter>(
        (ref, filter) async {
  ref.watch(ledgerProvider.select((s) => s.rows.length));

  final query = LedgerQuery(unresolved: filter);
  final result = await SupabaseService().client.rpc(
        'get_transaction_page',
        params: query.toParams(limit: 100),
      );
  return LedgerPage.fromRpc(Map<String, dynamic>.from(result as Map)).rows;
});

/// Count of expenses whose amount is attributed to nothing. Drives the ledger
/// banner, so it must reflect the whole ledger, not the current page.
final needsPrimaryCountProvider = Provider<int>((ref) {
  return ref.watch(briefingSummaryProvider(null)).maybeWhen(
        data: (s) => s.needsPrimaryCount,
        orElse: () => 0,
      );
});
