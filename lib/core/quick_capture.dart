import '../models/account.dart';
import '../models/transaction_label.dart';

/// A parsed but unsaved quick-capture draft (TODO 10.1).
///
/// Every field is nullable and every uncertainty is recorded in [warnings]:
/// the parser produces a draft to confirm, never a save. Ambiguous input yields
/// a partial draft, so nothing is ever silently saved wrong.
class CaptureDraft {
  const CaptureDraft({
    this.amount,
    this.type = 'debit',
    this.accountId,
    this.merchant,
    this.primaryLabelId,
    this.warnings = const [],
    required this.raw,
  });

  final double? amount;

  /// `debit` (default) or `credit`. Transfers/investments need two accounts
  /// and are out of scope for one-field capture.
  final String type;
  final String? accountId;
  final String? merchant;
  final String? primaryLabelId;

  /// What could not be resolved, shown on the confirmation sheet.
  final List<String> warnings;
  final String raw;

  bool get isExpense => type == 'debit';

  /// The minimum a save needs: an amount and an account. A labelled expense
  /// still has to name a primary, but the confirm sheet handles that, matching
  /// `save_transaction_with_labels`.
  bool get isComplete => amount != null && accountId != null;

  CaptureDraft copyWith({
    double? amount,
    String? type,
    String? accountId,
    String? merchant,
    String? primaryLabelId,
    List<String>? warnings,
  }) =>
      CaptureDraft(
        amount: amount ?? this.amount,
        type: type ?? this.type,
        accountId: accountId ?? this.accountId,
        merchant: merchant ?? this.merchant,
        primaryLabelId: primaryLabelId ?? this.primaryLabelId,
        warnings: warnings ?? this.warnings,
        raw: raw,
      );
}

/// Deterministic quick-capture parser. Tried FIRST, before any AI: it is
/// predictable, offline, private, and free, and the roadmap reserves Gemini for
/// the fallback path. It never saves — it fills a draft for confirmation.
class QuickCaptureParser {
  const QuickCaptureParser({
    required this.accounts,
    required this.labels,
  });

  final List<Account> accounts;
  final List<TransactionLabel> labels;

  /// Words that flip the draft to income. Anything else defaults to an expense,
  /// which is the overwhelmingly common quick-capture case.
  static const _incomeWords = {
    'received', 'refund', 'refunded', 'salary', 'income', 'credited', 'earned',
  };

  /// Words that signal an outflow to another person — captured as a normal
  /// expense (the FAMILY label makes it Family Support, not the parser).
  static const _sentWords = {'sent', 'paid', 'gave', 'transfer', 'transferred'};

  /// Filler tokens that never form part of a merchant name.
  static const _stopWords = {
    'to', 'for', 'in', 'on', 'at', 'the', 'a', 'via', 'using', 'from', 'with',
    'rs', 'rs.', 'inr', '₹',
  };

  CaptureDraft parse(String input) {
    final raw = input.trim();
    final warnings = <String>[];
    if (raw.isEmpty) {
      return const CaptureDraft(raw: '', warnings: ['Nothing entered.']);
    }

    final tokens = raw.split(RegExp(r'\s+'));
    final lower = tokens.map((t) => t.toLowerCase()).toList();

    // --- Amount: the first bare number, ₹-prefixed or not. -------------------
    double? amount;
    var amountMatches = 0;
    for (final token in tokens) {
      final cleaned = token.replaceAll(RegExp(r'[₹,]'), '');
      final value = double.tryParse(cleaned);
      if (value != null && value > 0) {
        amount ??= value;
        amountMatches++;
      }
    }
    if (amount == null) {
      warnings.add('No amount found.');
    } else if (amountMatches > 1) {
      warnings.add('Multiple numbers — used the first ($amount). Check it.');
    }

    // --- Direction ----------------------------------------------------------
    final type =
        lower.any(_incomeWords.contains) ? 'credit' : 'debit';

    // --- Account: longest matching account name wins, so "kotak bank" beats
    //     a stray "cash". ------------------------------------------------------
    String? accountId;
    var bestLen = 0;
    for (final account in accounts) {
      final name = account.name.toLowerCase();
      final hit = lower.contains(name) ||
          name.split(' ').every(lower.contains) && name.isNotEmpty;
      if (hit && name.length > bestLen) {
        accountId = account.id;
        bestLen = name.length;
      }
    }
    // A cash keyword is a common shorthand even without a "Cash" account named.
    if (accountId == null && lower.contains('cash')) {
      final cash = accounts
          .where((a) => a.type == 'cash')
          .cast<Account?>()
          .firstWhere((_) => true, orElse: () => null);
      accountId = cash?.id;
    }
    if (accountId == null) {
      warnings.add('No account recognised — choose one below.');
    }

    // --- Label: first keyword match against an active label name. -----------
    String? primaryLabelId;
    for (final label in labels) {
      if (!label.isAssignable || label.id == null) continue;
      if (lower.contains(label.name.toLowerCase())) {
        primaryLabelId = label.id;
        break;
      }
    }

    // --- Merchant / note: the leftover words. -------------------------------
    final accountWords = accountId == null
        ? <String>{}
        : accounts
            .firstWhere((a) => a.id == accountId)
            .name
            .toLowerCase()
            .split(' ')
            .toSet();
    final labelWord = primaryLabelId == null
        ? null
        : labels
            .firstWhere((l) => l.id == primaryLabelId)
            .name
            .toLowerCase();

    final merchantTokens = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final w = lower[i];
      if (double.tryParse(tokens[i].replaceAll(RegExp(r'[₹,]'), '')) != null) {
        continue;
      }
      if (_stopWords.contains(w) ||
          _sentWords.contains(w) ||
          _incomeWords.contains(w) ||
          accountWords.contains(w) ||
          w == 'cash' ||
          w == labelWord) {
        continue;
      }
      merchantTokens.add(tokens[i]);
    }
    final merchant = merchantTokens.isEmpty ? null : merchantTokens.join(' ');

    return CaptureDraft(
      raw: raw,
      amount: amount,
      type: type,
      accountId: accountId,
      merchant: merchant,
      primaryLabelId: primaryLabelId,
      warnings: warnings,
    );
  }
}
