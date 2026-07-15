/// Freelance invoice with a 3-column payout breakdown.
///
/// [receivedBank] is stored in INR. [paypalFee], [fxLoss], and [fxRate] are
/// derived display fields computed from the received amounts. [computedStatus]
/// mirrors the SQL-free client-side status derivation.
class Invoice {
  final String? id;
  final String client;
  final String? description;
  final double invoicedUsd;
  final double receivedPaypal;

  /// Bank receipts are tracked in INR so the app can show the rupee amount
  /// users actually saw in their bank account.
  final double receivedBank;
  final double? paypalFee;
  final double? fxLoss;
  final double? fxRate;
  final String status;
  final DateTime? invoiceDate;
  final bool isDeleted;
  final DateTime? deletedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Invoice({
    this.id,
    required this.client,
    this.description,
    required this.invoicedUsd,
    this.receivedPaypal = 0,
    this.receivedBank = 0,
    this.paypalFee,
    this.fxLoss,
    this.fxRate,
    this.status = 'pending',
    this.invoiceDate,
    this.isDeleted = false,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  double get receivedBankUsdEquivalent {
    final rate = fxRate;
    if (rate != null && rate > 0) {
      return receivedBank / rate;
    }
    return receivedBank;
  }

  double get totalReceived => receivedPaypal + receivedBankUsdEquivalent;
  double get difference => invoicedUsd - receivedPaypal;
  double get outstanding => difference;

  String get computedStatus {
    if (totalReceived >= invoicedUsd) return 'paid';
    if (totalReceived > 0) return 'partial';
    return 'pending';
  }

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: json['id'] as String?,
      client: json['client'] as String,
      description: json['description'] as String?,
      invoicedUsd: (json['invoiced_usd'] as num).toDouble(),
      receivedPaypal: (json['received_paypal'] as num?)?.toDouble() ?? 0,
      receivedBank: (json['received_bank'] as num?)?.toDouble() ?? 0,
      paypalFee: (json['paypal_fee'] as num?)?.toDouble(),
      fxLoss: (json['fx_loss'] as num?)?.toDouble(),
      fxRate: (json['fx_rate'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'pending',
      invoiceDate: json['invoice_date'] != null
          ? DateTime.parse(json['invoice_date'] as String)
          : null,
      isDeleted: json['is_deleted'] as bool? ?? false,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'client': client,
      'description': description,
      'invoiced_usd': invoicedUsd,
      'received_paypal': receivedPaypal,
      'received_bank': receivedBank,
      'paypal_fee': paypalFee,
      'fx_loss': fxLoss,
      'fx_rate': fxRate,
      'status': computedStatus,
      'invoice_date': invoiceDate?.toIso8601String(),
    };
  }
}
