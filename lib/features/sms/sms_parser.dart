import '../../models/transaction.dart';

class SmsParser {
  static final List<_PatternDef> _patterns = [
    _PatternDef(
      regex: RegExp(r'[₹R]\s*([\d,]+\.?\d*)\s*(debited|credited|spent|received|paid)\s*(?:from|to|via)?\s*(\w+)?', caseSensitive: false),
      amountGroup: 1,
      actionGroup: 2,
      merchantGroup: 3,
    ),
    _PatternDef(
      regex: RegExp(r'Rs\.?\s*([\d,]+\.?\d*)\s*(debited|credited|spent|received|paid)\s*(?:at|from|to)?\s*(\w+)?', caseSensitive: false),
      amountGroup: 1,
      actionGroup: 2,
      merchantGroup: 3,
    ),
    _PatternDef(
      regex: RegExp(r'Trf\s+(?:to|from)\s+(\w+)\s+[₹R]\s*([\d,]+\.?\d*)', caseSensitive: false),
      amountGroup: 2,
      actionGroup: null,
      merchantGroup: 1,
    ),
    _PatternDef(
      regex: RegExp(r'(?:Rs|₹|INR)\s*[:\s]*([\d,]+\.?\d*)\s*(?:is\s+)?(?:debited|credited)\s+[\w\s]+?(?:from|to|at)\s+(\w+)', caseSensitive: false),
      amountGroup: 1,
      actionGroup: null,
      merchantGroup: 2,
    ),
  ];

  static Transaction? parse(String sms) {
    if (sms.isEmpty) return null;

    for (final def in _patterns) {
      final match = def.regex.firstMatch(sms);
      if (match == null) continue;

      final amountStr = match.group(def.amountGroup);
      if (amountStr == null) continue;

      final amount = double.tryParse(amountStr.replaceAll(',', ''));
      if (amount == null) continue;

      final action = def.actionGroup != null ? (match.group(def.actionGroup)?.toLowerCase() ?? '') : '';
      final merchant = def.merchantGroup != null ? match.group(def.merchantGroup!) : null;

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

    return null;
  }
}

class _PatternDef {
  final RegExp regex;
  final int amountGroup;
  final int? actionGroup;
  final int? merchantGroup;

  const _PatternDef({
    required this.regex,
    required this.amountGroup,
    this.actionGroup,
    this.merchantGroup,
  });
}
