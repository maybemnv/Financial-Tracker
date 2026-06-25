import 'dart:convert';

/// A single ledger entry: debit, credit, transfer leg, or investment.
///
/// Transfers are double-entry — two rows linked by [transferGroupId]. Net worth
/// is unaffected by transfers and investments (money moves between accounts).
class Transaction {
  final String? id;
  final String? accountId;
  final double amount;
  final String type; // debit | credit | transfer | investment
  final String? vpa;
  final String? merchant;
  final String? bank;
  final String? category;
  final List<String> tags;
  final String? rawSms;
  final String? rawSmsHash;
  final String source; // sms | manual
  final String? note;
  final double? usdAmount;
  final String? linkedInvoiceId;
  final String? transferGroupId;
  final bool isDeleted;
  final DateTime? deletedAt;
  final List<Map<String, dynamic>> editHistory;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Transaction({
    this.id,
    this.accountId,
    required this.amount,
    required this.type,
    this.vpa,
    this.merchant,
    this.bank,
    this.category,
    this.tags = const [],
    this.rawSms,
    this.rawSmsHash,
    this.source = 'manual',
    this.note,
    this.usdAmount,
    this.linkedInvoiceId,
    this.transferGroupId,
    this.isDeleted = false,
    this.deletedAt,
    this.editHistory = const [],
    this.createdAt,
    this.updatedAt,
  });

  bool get isCredit => type == 'credit';
  bool get isTransfer => type == 'transfer';
  bool get isInvestment => type == 'investment';

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as String?,
      accountId: json['account_id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      type: json['type'] as String,
      vpa: json['vpa'] as String?,
      merchant: json['merchant'] as String?,
      bank: json['bank'] as String?,
      category: json['category'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      rawSms: json['raw_sms'] as String?,
      rawSmsHash: json['raw_sms_hash'] as String?,
      source: json['source'] as String? ?? 'manual',
      note: json['note'] as String?,
      usdAmount: (json['usd_amount'] as num?)?.toDouble(),
      linkedInvoiceId: json['linked_invoice_id'] as String?,
      transferGroupId: json['transfer_group_id'] as String?,
      isDeleted: json['is_deleted'] as bool? ?? false,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      editHistory: (json['edit_history'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  /// Payload for INSERT/UPDATE. Omits server-managed fields (id, timestamps,
  /// is_deleted, edit_history) so writes never clobber them.
  Map<String, dynamic> toJson() {
    return {
      if (accountId != null) 'account_id': accountId,
      'amount': amount,
      'type': type,
      'vpa': vpa,
      'merchant': merchant,
      'bank': bank,
      'category': category,
      'tags': tags,
      'raw_sms': rawSms,
      'raw_sms_hash': rawSmsHash,
      'source': source,
      'note': note,
      'usd_amount': usdAmount,
      'linked_invoice_id': linkedInvoiceId,
      'transfer_group_id': transferGroupId,
    };
  }

  Transaction copyWith({
    String? id,
    String? accountId,
    double? amount,
    String? type,
    String? vpa,
    String? merchant,
    String? bank,
    String? category,
    List<String>? tags,
    String? rawSms,
    String? rawSmsHash,
    String? source,
    String? note,
    double? usdAmount,
    String? linkedInvoiceId,
    String? transferGroupId,
    bool? isDeleted,
    DateTime? deletedAt,
    List<Map<String, dynamic>>? editHistory,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      vpa: vpa ?? this.vpa,
      merchant: merchant ?? this.merchant,
      bank: bank ?? this.bank,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      rawSms: rawSms ?? this.rawSms,
      rawSmsHash: rawSmsHash ?? this.rawSmsHash,
      source: source ?? this.source,
      note: note ?? this.note,
      usdAmount: usdAmount ?? this.usdAmount,
      linkedInvoiceId: linkedInvoiceId ?? this.linkedInvoiceId,
      transferGroupId: transferGroupId ?? this.transferGroupId,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      editHistory: editHistory ?? this.editHistory,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// JSON-encodes the edit-history audit trail for the SQL `edit_history`
  /// column (append-only `[{"old": {...}, "new": {...}, "edited_at": "..."}]`).
  static String encodeEditHistory(List<Map<String, dynamic>> history) =>
      jsonEncode(history);
}
