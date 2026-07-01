import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/features/sms/sms_parser.dart';

void main() {
  group('SmsParser', () {
    test('parses valid HDFC debit SMS', () {
      final tx = SmsParser.parse(
        'Rs.1,250.50 debited from a/c XX1234 to SWIGGY on 01/07/2026 at 19:45. UPI Ref 123.',
        sender: 'VM-HDFCBK',
      );

      expect(tx, isNotNull,
          reason: 'A valid HDFC debit SMS should produce a transaction.');
      expect(tx!.amount, 1250.50,
          reason: 'Debit SMS amount should parse commas and decimals.');
      expect(tx.type, 'debit',
          reason: 'HDFC debited wording should map to debit.');
      expect(tx.bank, 'HDFC',
          reason: 'Sender VM-HDFCBK should map the transaction bank to HDFC.');
      expect(tx.merchant, 'SWIGGY',
          reason: 'The merchant after "to" should be captured.');
      expect(tx.transactedAt, DateTime(2026, 7, 1, 19, 45),
          reason: 'SMS date and 24-hour time should populate transactedAt.');
    });

    test('parses valid SBI credit SMS', () {
      final tx = SmsParser.parse(
        'Your SBI A/c credited by INR 50,000.00 from ACME PAYROLL on 02-Jul-2026 09:10.',
        sender: 'BP-SBIBNK',
      );

      expect(tx, isNotNull,
          reason: 'A valid SBI credit SMS should produce a transaction.');
      expect(tx!.amount, 50000,
          reason: 'Credit SMS amount should parse INR values with commas.');
      expect(tx.type, 'credit',
          reason: 'SBI credited wording should map to credit.');
      expect(tx.bank, 'SBI',
          reason: 'Sender BP-SBIBNK should map the transaction bank to SBI.');
      expect(tx.merchant, 'ACME PAYROLL',
          reason: 'The source after "from" should be captured for credits.');
      expect(tx.transactedAt, DateTime(2026, 7, 2, 9, 10),
          reason: 'Named month dates should populate transactedAt.');
    });

    test('returns null when no amount is detected', () {
      final tx = SmsParser.parse(
        'Your Kotak account statement is ready for download.',
        sender: 'VK-KOTAKB',
      );

      expect(tx, isNull,
          reason:
              'SMS without an amount must be ignored instead of creating a zero-value transaction.');
    });

    test('returns null for unrecognised sender', () {
      final tx = SmsParser.parse(
        'Rs.500 debited to SOME MERCHANT on 01/07/2026.',
        sender: 'AD-RANDOM',
      );

      expect(tx, isNull,
          reason:
              'Unrecognised senders must be ignored to avoid parsing promotional or spoofed SMS.');
    });

    test('parses ICICI, Kotak, and PayPal sender families', () {
      final icici = SmsParser.parse(
        'ICICI Bank Acct XX123 debited for Rs.250.00 at METRO on 01-Jul-2026.',
        sender: 'JD-ICICIB',
      );
      final kotak = SmsParser.parse(
        'Spent Rs.120.50 from Kotak Bank AC XX1234 at PAYTM on 01-07-2026.',
        sender: 'VK-KOTAKB',
      );
      final paypal = SmsParser.parse(
        'You received INR 5,000.00 from CLIENT LLC on 1 Jul 2026 in your PayPal account.',
        sender: 'PAYPAL',
      );

      expect(icici?.bank, 'ICICI',
          reason: 'ICICI sender names must be recognised.');
      expect(kotak?.bank, 'Kotak',
          reason: 'Kotak sender names must be recognised.');
      expect(paypal?.bank, 'PayPal',
          reason: 'PayPal sender names must be recognised.');
      expect(paypal?.type, 'credit',
          reason: 'PayPal received wording should map to credit.');
    });
  });
}
