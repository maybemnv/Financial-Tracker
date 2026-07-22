/// An expected recurring inflow (Salary, Freelance retainer, Rent...). Enables
/// agent questions like "How much income should I expect in July?"
class RecurringIncome {
  final String? id;
  final String name;
  final double amount;
  final String frequency; // monthly | weekly | yearly
  final String? source;
  final DateTime? nextExpected;
  final DateTime? createdAt;

  /// Account the money is expected to move through, when known (Phase 9.1).
  final String? accountId;

  /// Paused obligations are listed but excluded from the forecast.
  final bool isPaused;

  /// The ledger row that settled the current cycle, and the due date it
  /// settled. Without this link a confirmed obligation would keep appearing in
  /// the forecast beside the transaction that already paid it.
  final String? confirmedTransactionId;
  final DateTime? confirmedFor;

  final bool isDeleted;

  RecurringIncome({
    this.id,
    required this.name,
    required this.amount,
    required this.frequency,
    this.source,
    this.nextExpected,
    this.createdAt,
    this.accountId,
    this.isPaused = false,
    this.confirmedTransactionId,
    this.confirmedFor,
    this.isDeleted = false,
  });

  factory RecurringIncome.fromJson(Map<String, dynamic> json) {
    return RecurringIncome(
      id: json['id'] as String?,
      name: json['name'] as String,
      amount: (json['amount'] as num).toDouble(),
      frequency: json['frequency'] as String,
      source: json['source'] as String?,
      nextExpected: json['next_expected'] != null
          ? DateTime.parse(json['next_expected'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      accountId: json['account_id'] as String?,
      isPaused: json['is_paused'] as bool? ?? false,
      confirmedTransactionId: json['confirmed_transaction_id'] as String?,
      confirmedFor: json['confirmed_for'] != null
          ? DateTime.parse(json['confirmed_for'] as String)
          : null,
      isDeleted: json['is_deleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'amount': amount,
      'frequency': frequency,
      'source': source,
      'next_expected': nextExpected?.toIso8601String(),
    };
  }
}
