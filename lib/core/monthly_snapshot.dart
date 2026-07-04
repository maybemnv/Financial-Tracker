import '../models/monthly_snapshot.dart';
import 'supabase.dart';

/// Backfills the previous month's aggregate into `monthly_snapshots` on first
/// open of a new month. Append-only (UNIQUE month+year) — re-runs are no-ops.
class MonthlySnapshotJob {
  /// Runs if there's no snapshot row for last month. Silent on failure — this
  /// is best-effort housekeeping, never blocks app launch.
  static Future<void> runIfNeeded() async {
    try {
      final now = DateTime.now();
      final last =
          DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));
      final client = SupabaseService().client;

      final existing = await client
          .from('monthly_snapshots')
          .select('id')
          .eq('month', last.month)
          .eq('year', last.year)
          .maybeSingle();
      if (existing != null) return;

      final rows = await client
          .from('transactions')
          .select('amount, type, direction, created_at, transacted_at')
          .eq('is_deleted', false);

      double income = 0;
      double expenses = 0;
      double investments = 0;
      for (final rawRow in (rows as List)) {
        final row = Map<String, dynamic>.from(rawRow as Map);
        final effectiveDate = _effectiveDate(row);
        if (effectiveDate == null ||
            effectiveDate.year != last.year ||
            effectiveDate.month != last.month) {
          continue;
        }

        final amount = (row['amount'] as num).toDouble();
        final type = row['type'] as String;
        final direction = row['direction'] as String?;
        switch (type) {
          case 'credit':
            income += amount;
            break;
          case 'debit':
            expenses += amount;
            break;
          case 'investment':
            if (direction != 'inflow') {
              investments += amount;
            }
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

      await client.from('monthly_snapshots').insert(
            MonthlySnapshot(
              month: last.month,
              year: last.year,
              income: income,
              expenses: expenses,
              investments: investments,
              savings: savings,
              savingsRate: savingsRate,
              netWorth: netWorth,
            ).toJson(),
          );
    } catch (_) {
      // Best-effort — never crash the app over a missed snapshot.
    }
  }

  static DateTime? _effectiveDate(Map<String, dynamic> row) {
    final transactedAt = row['transacted_at'] as String?;
    if (transactedAt != null && transactedAt.isNotEmpty) {
      return DateTime.tryParse(transactedAt);
    }
    final createdAt = row['created_at'] as String?;
    if (createdAt != null && createdAt.isNotEmpty) {
      return DateTime.tryParse(createdAt);
    }
    return null;
  }
}
