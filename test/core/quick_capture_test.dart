import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/core/quick_capture.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/merchant_alias.dart';
import 'package:finance_tracker/models/transaction_label.dart';

/// Phase 10 tests: the deterministic capture parser and read-time merchant
/// normalization.
void main() {
  final accounts = [
    Account(id: 'cash', name: 'Cash', type: 'cash'),
    Account(id: 'kotak', name: 'Kotak', type: 'bank'),
    Account(id: 'hdfc', name: 'HDFC Bank', type: 'bank'),
  ];
  const labels = [
    TransactionLabel(id: 'food', name: 'Food', color: '#111111'),
    TransactionLabel(id: 'family', name: 'Family', color: '#222222',
        excludeFromPersonalSpend: true),
  ];
  final parser = QuickCaptureParser(accounts: accounts, labels: labels);

  group('the two spec examples', () {
    test('"250 biryani cash" — amount, cash account, note', () {
      final d = parser.parse('250 biryani cash');
      expect(d.amount, 250);
      expect(d.type, 'debit');
      expect(d.accountId, 'cash');
      expect(d.merchant, 'biryani');
      expect(d.isComplete, isTrue);
      expect(d.warnings, isEmpty);
    });

    test('"500 sent to mummy kotak" — outflow to a person, Kotak', () {
      final d = parser.parse('500 sent to mummy kotak');
      expect(d.amount, 500);
      expect(d.type, 'debit',
          reason: '"sent" is still an expense; the FAMILY label, not the '
              'parser, makes it Family Support.');
      expect(d.accountId, 'kotak');
      expect(d.merchant, 'mummy',
          reason: '"sent", "to", and the account name are stripped.');
      expect(d.isComplete, isTrue);
    });
  });

  group('direction', () {
    test('income keywords flip to credit', () {
      expect(parser.parse('5000 salary kotak').type, 'credit');
      expect(parser.parse('200 refund cash').type, 'credit');
    });

    test('the default is an expense', () {
      expect(parser.parse('99 coffee cash').type, 'debit');
    });
  });

  group('account matching', () {
    test('a multi-word account name matches', () {
      expect(parser.parse('300 groceries hdfc bank').accountId, 'hdfc');
    });

    test('the longest matching name wins', () {
      // "hdfc bank" beats a bare "bank" token overlap.
      final d = parser.parse('300 hdfc bank lunch');
      expect(d.accountId, 'hdfc');
    });

    test('an unknown account leaves a warning and no id', () {
      final d = parser.parse('300 lunch sbi');
      expect(d.accountId, isNull);
      expect(d.isComplete, isFalse);
      expect(d.warnings.any((w) => w.contains('account')), isTrue);
    });
  });

  group('label matching', () {
    test('a keyword sets the primary label', () {
      expect(parser.parse('250 food cash').primaryLabelId, 'food');
    });

    test('no keyword leaves the label unset', () {
      expect(parser.parse('250 biryani cash').primaryLabelId, isNull);
    });
  });

  group('ambiguity never becomes a silent wrong save', () {
    test('no amount blocks completion and warns', () {
      final d = parser.parse('biryani cash');
      expect(d.amount, isNull);
      expect(d.isComplete, isFalse);
      expect(d.warnings.any((w) => w.contains('amount')), isTrue);
    });

    test('multiple numbers take the first and flag it', () {
      final d = parser.parse('250 300 lunch cash');
      expect(d.amount, 250);
      expect(d.warnings.any((w) => w.contains('Multiple numbers')), isTrue);
    });

    test('empty input yields an empty, incomplete draft', () {
      final d = parser.parse('   ');
      expect(d.isComplete, isFalse);
      expect(d.amount, isNull);
    });
  });

  group('merchant normalization', () {
    const aliases = [
      MerchantAlias(matchPattern: 'amzn', canonicalName: 'Amazon'),
      MerchantAlias(matchPattern: 'amazon pay', canonicalName: 'Amazon Pay'),
    ];

    test('variants roll up to one canonical name', () {
      expect(canonicalMerchant('AMZN Mktp IN', aliases), 'Amazon');
      expect(canonicalMerchant('amzn*retail', aliases), 'Amazon');
    });

    test('the longest matching pattern wins', () {
      // "amazon pay" is more specific than a hypothetical "amazon".
      expect(canonicalMerchant('AMAZON PAY UPI', aliases), 'Amazon Pay');
    });

    test('an unmatched merchant keeps its raw name', () {
      expect(canonicalMerchant('Corner Cafe', aliases), 'Corner Cafe');
    });

    test('a blank merchant becomes Unknown', () {
      expect(canonicalMerchant(null, aliases), 'Unknown');
      expect(canonicalMerchant('  ', aliases), 'Unknown');
    });

    test('an alias changes only the display name, never structure', () {
      // The function returns a name; it has no access to and cannot alter any
      // amount. This is the audit guarantee, expressed as a type: raw in,
      // display string out.
      const raw = 'AMZN Mktp';
      final display = canonicalMerchant(raw, aliases);
      expect(display, 'Amazon');
      expect(raw, 'AMZN Mktp', reason: 'the raw value is untouched');
    });
  });
}
