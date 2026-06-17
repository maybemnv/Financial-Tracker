class Invoice {
  final String? id;
  final String client;
  final String? description;
  final double invoicedUsd;
  final double receivedPaypal;
  final double receivedBank;
  final String status;
  final DateTime? invoiceDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Invoice({
    this.id,
    required this.client,
    this.description,
    required this.invoicedUsd,
    this.receivedPaypal = 0,
    this.receivedBank = 0,
    this.status = 'pending',
    this.invoiceDate,
    this.createdAt,
    this.updatedAt,
  });

  double get totalReceived => receivedPaypal + receivedBank;
  double get outstanding => invoicedUsd - totalReceived;

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
      status: json['status'] as String? ?? 'pending',
      invoiceDate: json['invoice_date'] != null ? DateTime.parse(json['invoice_date'] as String) : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
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
      'status': status,
      'invoice_date': invoiceDate?.toIso8601String(),
    };
  }
}
