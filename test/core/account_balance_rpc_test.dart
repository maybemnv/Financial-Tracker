import 'package:flutter_test/flutter_test.dart';

class _MockFnAccountBalanceRpc {
  _MockFnAccountBalanceRpc({
    required this.openingBalance,
    required this.rows,
    required this.from,
    required this.to,
  });

  final double openingBalance;
  final List<Map<String, Object?>> rows;
  final DateTime from;
  final DateTime to;

  double call() {
    var balance = openingBalance;
    for (final row in rows) {
      final effectiveDate =
          (row['transacted_at'] as DateTime?) ?? row['created_at'] as DateTime?;
      if (effectiveDate == null ||
          effectiveDate.isBefore(from) ||
          !effectiveDate.isBefore(to)) {
        continue;
      }

      final amount = row['amount'] as double;
      switch (row['type']) {
        case 'credit':
          balance += amount;
          break;
        case 'debit':
          balance -= amount;
          break;
      }
    }
    return balance;
  }
}

void main() {
  group('fn_account_balance mocked COALESCE behavior', () {
    test('uses transacted_at before created_at when filtering RPC rows', () {
      final rpc = _MockFnAccountBalanceRpc(
        openingBalance: 1000,
        from: DateTime(2026, 6),
        to: DateTime(2026, 7),
        rows: [
          {
            'amount': 300.0,
            'type': 'debit',
            'created_at': DateTime(2026, 7, 1),
            'transacted_at': DateTime(2026, 6, 30),
          },
        ],
      );

      expect(
        rpc(),
        700,
        reason:
            'Mocked fn_account_balance must use COALESCE(transacted_at, created_at), so a June transaction created in July affects June balance.',
      );
    });

    test('falls back to created_at when transacted_at is null', () {
      final rpc = _MockFnAccountBalanceRpc(
        openingBalance: 1000,
        from: DateTime(2026, 7),
        to: DateTime(2026, 8),
        rows: [
          {
            'amount': 500.0,
            'type': 'credit',
            'created_at': DateTime(2026, 7, 2),
            'transacted_at': null,
          },
        ],
      );

      expect(
        rpc(),
        1500,
        reason:
            'Mocked fn_account_balance must fall back to created_at for legacy rows where transacted_at is null.',
      );
    });
  });
}
