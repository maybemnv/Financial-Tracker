/// A known recurring outflow (Spotify, SBI SIP, Netflix...). Used by the agent
/// to compute "committed money" — what's already spoken for before the month
/// begins.
class RecurringExpense {
  final String? id;
  final String name;
  final double amount;
  final String frequency; // monthly | weekly | yearly
  final String? category;
  final DateTime? nextDue;
  final DateTime? createdAt;

  RecurringExpense({
    this.id,
    required this.name,
    required this.amount,
    required this.frequency,
    this.category,
    this.nextDue,
    this.createdAt,
  });

  factory RecurringExpense.fromJson(Map<String, dynamic> json) {
    return RecurringExpense(
      id: json['id'] as String?,
      name: json['name'] as String,
      amount: (json['amount'] as num).toDouble(),
      frequency: json['frequency'] as String,
      category: json['category'] as String?,
      nextDue: json['next_due'] != null
          ? DateTime.parse(json['next_due'] as String)
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
      'category': category,
      'next_due': nextDue?.toIso8601String(),
    };
  }
}
