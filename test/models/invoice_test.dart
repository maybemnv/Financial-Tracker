import 'package:finance_tracker/models/invoice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Invoice totals', () {
    test('converts INR bank receipts through fxRate when computing totals', () {
      final invoice = Invoice(
        client: 'Client A',
        invoicedUsd: 1000,
        receivedPaypal: 250,
        receivedBank: 25000,
        fxRate: 50,
      );

      expect(invoice.receivedBankUsdEquivalent, 500);
      expect(invoice.totalReceived, 750);
      expect(invoice.difference, 750);
      expect(invoice.computedStatus, 'partial');
    });

    test('falls back to legacy direct sum when fxRate is absent', () {
      final invoice = Invoice(
        client: 'Client B',
        invoicedUsd: 1000,
        receivedPaypal: 250,
        receivedBank: 500,
      );

      expect(invoice.receivedBankUsdEquivalent, 500);
      expect(invoice.totalReceived, 750);
      expect(invoice.difference, 750);
    });
  });

  group('Invoice serialization', () {
    test('stores computed status in json', () {
      final invoice = Invoice(
        client: 'Client C',
        invoicedUsd: 100,
        receivedPaypal: 100,
      );

      expect(invoice.toJson()['status'], 'paid');
    });
  });
}
