/// A financial account (SBI, Kotak, PayPal, Cash, Nifty 50...). Balance is
/// derived via the `fn_account_balance` RPC — never stored, so there is no
/// `balance` field here.
class Account {
  final String? id;
  final String name;
  final String type; // cash | bank | paypal | investment
  final double openingBalance;
  final DateTime? openingDate;
  final bool isDeleted;
  final DateTime? deletedAt;
  final DateTime? createdAt;

  Account({
    this.id,
    required this.name,
    required this.type,
    this.openingBalance = 0,
    this.openingDate,
    this.isDeleted = false,
    this.deletedAt,
    this.createdAt,
  });

  bool get isInvestment => type == 'investment';

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String?,
      name: json['name'] as String,
      type: json['type'] as String,
      openingBalance: (json['opening_balance'] as num?)?.toDouble() ?? 0,
      openingDate: json['opening_date'] != null
          ? DateTime.parse(json['opening_date'] as String)
          : null,
      isDeleted: json['is_deleted'] as bool? ?? false,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'type': type,
      'opening_balance': openingBalance,
      'opening_date': openingDate?.toIso8601String(),
    };
  }
}
