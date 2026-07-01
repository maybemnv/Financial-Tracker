import '../../models/transaction.dart';

class SmsParser {
  static const _recognizedSenders = {
    'hdfc': 'HDFC',
    'sbi': 'SBI',
    'icici': 'ICICI',
    'kotak': 'Kotak',
    'paypal': 'PayPal',
  };

  static Transaction? parse(
    String sms, {
    String? sender,
    DateTime? receivedAt,
  }) {
    try {
      final body = sms.trim();
      if (body.isEmpty) return null;

      final bank = _bankFromSender(sender);
      if (bank == null) return null;

      final amount = _extractAmount(body);
      if (amount == null) return null;

      final type = _extractType(body);
      if (type == null) return null;

      final merchant = _extractMerchant(body, type);
      final transactedAt = _extractDate(body) ?? receivedAt;

      return Transaction(
        amount: amount,
        type: type,
        merchant: merchant,
        bank: bank,
        source: 'sms',
        rawSms: body,
        transactedAt: transactedAt,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _bankFromSender(String? sender) {
    final normalized = sender?.toLowerCase() ?? '';
    for (final entry in _recognizedSenders.entries) {
      if (normalized.contains(entry.key)) return entry.value;
    }
    return null;
  }

  static double? _extractAmount(String body) {
    final patterns = [
      RegExp(r'(?:rs\.?|inr|\u20b9)\s*([0-9,]+(?:\.[0-9]{1,2})?)',
          caseSensitive: false),
      RegExp(r'([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:rs\.?|inr)',
          caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      final raw = match?.group(1);
      if (raw == null) continue;
      final amount = double.tryParse(raw.replaceAll(',', ''));
      if (amount != null) return amount;
    }
    return null;
  }

  static String? _extractType(String body) {
    final normalized = body.toLowerCase();
    const creditWords = [
      'credited',
      'credit',
      'received',
      'deposited',
      'refund',
      'added',
    ];
    const debitWords = [
      'debited',
      'debit',
      'spent',
      'paid',
      'withdrawn',
      'sent',
      'purchase',
    ];

    final creditIndex = _firstWordIndex(normalized, creditWords);
    final debitIndex = _firstWordIndex(normalized, debitWords);

    if (creditIndex == null && debitIndex == null) return null;
    if (creditIndex == null) return 'debit';
    if (debitIndex == null) return 'credit';
    return creditIndex < debitIndex ? 'credit' : 'debit';
  }

  static int? _firstWordIndex(String input, List<String> words) {
    int? first;
    for (final word in words) {
      final index = input.indexOf(word);
      if (index == -1) continue;
      first = first == null || index < first ? index : first;
    }
    return first;
  }

  static String? _extractMerchant(String body, String type) {
    final patterns = type == 'credit'
        ? [
            RegExp(r'from\s+([a-z0-9 .&_-]{2,40}?)(?:\s+(?:on|ref|upi|txn|imps|neft|with)|[.;,]|$)',
                caseSensitive: false),
            RegExp(r'by\s+(?!rs\.?\b|inr\b|\u20b9)([a-z0-9 .&_-]{2,40}?)(?:\s+(?:on|ref|upi|txn|imps|neft|with)|[.;,]|$)',
                caseSensitive: false),
          ]
        : [
            RegExp(r'(?:at|to|towards|paid to|sent to)\s+([a-z0-9 .&_-]{2,40}?)(?:\s+(?:on|ref|upi|txn|imps|neft|with)|[.;,]|$)',
                caseSensitive: false),
          ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      final raw = match?.group(1);
      final cleaned = _cleanMerchant(raw);
      if (cleaned != null) return cleaned;
    }
    return null;
  }

  static String? _cleanMerchant(String? raw) {
    final cleaned = raw
        ?.replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^a-zA-Z0-9 .&_-]'), '')
        .trim();
    if (cleaned == null || cleaned.length < 2) return null;
    final lower = cleaned.toLowerCase();
    if (lower.startsWith('a/c') || lower.startsWith('ac ')) return null;
    return cleaned;
  }

  static DateTime? _extractDate(String body) {
    final numeric = RegExp(r'\b(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})\b')
        .firstMatch(body);
    if (numeric != null) {
      final day = int.tryParse(numeric.group(1)!);
      final month = int.tryParse(numeric.group(2)!);
      final year = _normalizeYear(int.tryParse(numeric.group(3)!));
      return _dateWithOptionalTime(body, day, month, year);
    }

    final named =
        RegExp(r'\b(\d{1,2})[-\s]([a-z]{3,9})[-\s](\d{2,4})\b',
                caseSensitive: false)
            .firstMatch(body);
    if (named != null) {
      final day = int.tryParse(named.group(1)!);
      final month = _monthNumber(named.group(2)!);
      final year = _normalizeYear(int.tryParse(named.group(3)!));
      return _dateWithOptionalTime(body, day, month, year);
    }

    return null;
  }

  static DateTime? _dateWithOptionalTime(
    String body,
    int? day,
    int? month,
    int? year,
  ) {
    if (day == null || month == null || year == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    var hour = 0;
    var minute = 0;
    final time =
        RegExp(r'\b(\d{1,2}):(\d{2})(?:\s*([ap]m))?\b', caseSensitive: false)
            .firstMatch(body);
    if (time != null) {
      hour = int.tryParse(time.group(1)!) ?? 0;
      minute = int.tryParse(time.group(2)!) ?? 0;
      final marker = time.group(3)?.toLowerCase();
      if (marker == 'pm' && hour < 12) hour += 12;
      if (marker == 'am' && hour == 12) hour = 0;
    }

    try {
      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  static int? _normalizeYear(int? year) {
    if (year == null) return null;
    if (year < 100) return 2000 + year;
    return year;
  }

  static int? _monthNumber(String month) {
    const months = {
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };
    return months[month.toLowerCase()];
  }
}
