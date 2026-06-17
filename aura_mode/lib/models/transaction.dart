class Transaction {
  final String? id;
  final double amount;
  final String type;
  final String? vpa;
  final String? merchant;
  final String? bank;
  final String? category;
  final List<String> tags;
  final String? rawSms;
  final String source;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Transaction({
    this.id,
    required this.amount,
    required this.type,
    this.vpa,
    this.merchant,
    this.bank,
    this.category,
    this.tags = const [],
    this.rawSms,
    this.source = 'manual',
    this.createdAt,
    this.updatedAt,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      type: json['type'] as String,
      vpa: json['vpa'] as String?,
      merchant: json['merchant'] as String?,
      bank: json['bank'] as String?,
      category: json['category'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      rawSms: json['raw_sms'] as String?,
      source: json['source'] as String? ?? 'manual',
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'amount': amount,
      'type': type,
      'vpa': vpa,
      'merchant': merchant,
      'bank': bank,
      'category': category,
      'tags': tags,
      'raw_sms': rawSms,
      'source': source,
    };
  }

  Transaction copyWith({
    String? id,
    double? amount,
    String? type,
    String? vpa,
    String? merchant,
    String? bank,
    String? category,
    List<String>? tags,
    String? rawSms,
    String? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      vpa: vpa ?? this.vpa,
      merchant: merchant ?? this.merchant,
      bank: bank ?? this.bank,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      rawSms: rawSms ?? this.rawSms,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
