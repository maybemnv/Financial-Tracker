import 'supabase.dart';
import '../models/monthly_snapshot.dart';

/// Backfills the previous month's aggregate into `monthly_snapshots` on first
/// open of a new month. Append-only (UNIQUE month+year) — re-runs are no-ops.
/// Uses snapshots for trend charts instead of recomputing from raw transactions
/// forever.
class MonthlySnapshotJob {
  /// Runs if there's no snapshot row for last month. Silent on failure — this
  /// is best-effort housekeeping, never blocks app launch.
  static Future<void> runIfNeeded() async {
    try {
      final now = DateTime.now();
      final last = DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));
      final client = SupabaseService().client;

      // Skip if last month is already recorded.
      final existing = await client
          .from('monthly_snapshots')
          .select('id')
          .eq('month', last.month)
          .eq('year', last.year)
          .maybeSingle();
      if (existing != null) return;

      final monthStart = DateTime(last.year, last.month, 1);
      final monthEnd = DateTime(last.year, last.month + 1, 1);

      final rows = await client
          .from('transactions')
          .select('amount, type')
          .eq('is_deleted', false)
          .gte('created_at', monthStart.toIso8601String())
          .lt('created_at', monthEnd.toIso8601String());

      double income = 0, expenses = 0, investments = 0;
      for (final r in (rows as List)) {
        final row = r as Map;
        final amt = (row['amount'] as num).toDouble();
        switch (row['type'] as String) {
          case 'credit':
            income += amt;
            break;
          case 'debit':
            expenses += amt;
            break;
          case 'investment':
            investments += amt;
            break;
        }
      }
      final savings = income - expenses;
      final savingsRate = income > 0 ? (savings / income) * 100 : 0.0;

      double netWorth = 0;
      try {
        final nw = await client.rpc('fn_net_worth');
        netWorth = (nw as num?)?.toDouble() ?? 0;
      } catch (_) {}

      await client.from('monthly_snapshots').insert(MonthlySnapshot(
        month: last.month,
        year: last.year,
        income: income,
        expenses: expenses,
        investments: investments,
        savings: savings,
        savingsRate: savingsRate,
        netWorth: netWorth,
      ).toJson());
    } catch (_) {
      // Best-effort — never crash the app over a missed snapshot.
    }
  }
}
