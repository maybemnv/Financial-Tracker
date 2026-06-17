import '../../models/transaction.dart';

class SmsParser {
  static final List<RegExp> _patterns = [
    // UPI: "₹500 debited from XXXXXX on 15-Jun via GooglePay. UPI: user@upi"
    RegExp(r'[₹R]\s*([\d,]+\.?\d*)\s*(debited|credited|spent|received|paid)\s*(?:from|to|via)?\s*(\w+)?',
        caseSensitive: false),
    // "Rs. 500.00 spent at Swiggy using UPI"
    RegExp(r'Rs\.?\s*([\d,]+\.?\d*)\s*(debited|credited|spent|received|paid)\s*(?:at|from|to)?\s*(\w+)?',
        caseSensitive: false),
    // "Trf to MERCHANT ₹500.00 UPI"
    RegExp(r'Trf\s+(?:to|from)\s+(\w+)\s+[₹R]\s*([\d,]+\.?\d*)',
        caseSensitive: false),
    // Generic: amount + debit/credit + merchant
    RegExp(r'(?:Rs|₹|INR)\s*[:\s]*([\d,]+\.?\d*)\s*(?:is\s+)?(?:debited|credited)\s+[\w\s]+?(?:from|to|at)\s+(\w+)',
        caseSensitive: false),
  ];

  static Transaction? parse(String sms) {
    if (sms.isEmpty) return null;

    String cleanAmount(String raw) => raw.replaceAll(',', '');

    for (final pattern in _patterns) {
      final match = pattern.firstMatch(sms);
      if (match != null) {
        final groups = match.groups([1, 2, 3]);
        final amountStr = groups[0];
        final action = groups[1]?.toLowerCase() ?? '';
        final merchant = groups[2];

        if (amountStr == null) continue;

        final amount = double.tryParse(cleanAmount(amountStr));
        if (amount == null) continue;

        final isCredit = action.contains('credit') || action.contains('received');
        final type = isCredit ? 'credit' : 'debit';

        return Transaction(
          amount: amount,
          type: type,
          merchant: merchant,
          source: 'sms',
          rawSms: sms,
        );
      }
    }

    return null;
  }
}
