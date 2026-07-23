import 'dart:convert';

import 'transaction_label.dart';

/// A single ledger entry: debit, credit, transfer leg, or investment leg.
///
/// [type] captures the semantic kind of transaction for reporting. [direction]
/// captures whether the row adds to or subtracts from the account balance.
class Transaction {
  final String? id;
  final String? accountId;
  final double amount;
  final String type; // debit | credit | transfer | investment
  final String? direction; // inflow | outflow
  final String? vpa;
  final String? merchant;
  final String? bank;
  final List<TransactionLabel> labels;
  final String? primaryLabelId; // the one label that attributes this expense
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
  final DateTime? transactedAt; // when the money actually moved (user-set)
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Transaction({
    this.id,
    this.accountId,
    required this.amount,
    required this.type,
    this.direction,
    this.vpa,
    this.merchant,
    this.bank,
    this.labels = const [],
    this.primaryLabelId,
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
    this.transactedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// The date/time used for display and grouping. Prefers transactedAt (user-set),
  /// falls back to createdAt (server timestamp), then now() as a last resort.
  DateTime get effectiveDate => transactedAt ?? createdAt ?? DateTime.now();

  bool get isCredit => type == 'credit';
  bool get isTransfer => type == 'transfer';
  bool get isInvestment => type == 'investment';
  bool get isPayPalPayoutOrDeposit {
    final merchantText = merchant?.toLowerCase() ?? '';
    final bankText = bank?.toLowerCase() ?? '';
    final noteText = note?.toLowerCase() ?? '';
    return merchantText.contains('paypal') ||
        bankText.contains('paypal') ||
        noteText.contains('paypal payout') ||
        noteText.contains('paypal deposit');
  }

  bool get isInflow =>
      direction != null ? direction == 'inflow' : type == 'credit';
  bool get isOutflow => !isInflow;

  /// The label that attributes this expense (PRD §4). Resolves the explicit
  /// [primaryLabelId] against [labels]; when unset, falls back to the sole
  /// attached label so single-label legacy rows still attribute correctly.
  TransactionLabel? get primaryLabel {
    if (primaryLabelId != null) {
      for (final label in labels) {
        if (label.id == primaryLabelId) return label;
      }
    }
    if (labels.length == 1) return labels.first;
    return null;
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as String?,
      accountId: json['account_id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      type: json['type'] as String,
      direction: json['direction'] as String?,
      vpa: json['vpa'] as String?,
      merchant: json['merchant'] as String?,
      bank: json['bank'] as String?,
      // `get_transaction_page` emits a flat `labels` array; a direct PostgREST
      // select embeds `transaction_labels(label:labels(*))`. Both are read.
      labels: _labelsFromJson(json['labels'] ?? json['transaction_labels']),
      primaryLabelId: json['primary_label_id'] as String?,
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
      transactedAt: json['transacted_at'] != null
          ? DateTime.parse(json['transacted_at'] as String)
          : null,
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
      if (direction != null) 'direction': direction,
      if (primaryLabelId != null) 'primary_label_id': primaryLabelId,
      'vpa': vpa,
      'merchant': merchant,
      'bank': bank,
      'raw_sms': rawSms,
      'raw_sms_hash': rawSmsHash,
      'source': source,
      'note': note,
      'usd_amount': usdAmount,
      'linked_invoice_id': linkedInvoiceId,
      'transfer_group_id': transferGroupId,
      if (transactedAt != null)
        'transacted_at': transactedAt!.toIso8601String(),
    };
  }

  Transaction copyWith({
    String? id,
    String? accountId,
    double? amount,
    String? type,
    String? direction,
    String? vpa,
    String? merchant,
    String? bank,
    List<TransactionLabel>? labels,
    String? primaryLabelId,
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
    DateTime? transactedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      direction: direction ?? this.direction,
      vpa: vpa ?? this.vpa,
      merchant: merchant ?? this.merchant,
      bank: bank ?? this.bank,
      labels: labels ?? this.labels,
      primaryLabelId: primaryLabelId ?? this.primaryLabelId,
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
      transactedAt: transactedAt ?? this.transactedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// JSON-encodes the edit-history audit trail for the SQL `edit_history`
  /// column (append-only `[{"old": {...}, "new": {...}, "edited_at": "..."}]`).
  static String encodeEditHistory(List<Map<String, dynamic>> history) =>
      jsonEncode(history);

  /// Accepts both label shapes the app receives:
  ///   RPC       `[{id, name, color, ...}]`              — flat
  ///   PostgREST `[{label: {id, name, color, ...}}]`     — embedded join row
  /// An entry carrying a nested `label` map is unwrapped; anything else is
  /// taken as the label itself.
  static List<TransactionLabel> _labelsFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((entry) {
          final nested = entry['label'];
          return nested is Map ? nested : entry;
        })
        .where((label) => label['name'] != null && label['color'] != null)
        .map((label) => TransactionLabel.fromJson(
              Map<String, dynamic>.from(label),
            ))
        .toList();
  }
}
