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

  RecurringIncome({
    this.id,
    required this.name,
    required this.amount,
    required this.frequency,
    this.source,
    this.nextExpected,
    this.createdAt,
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
