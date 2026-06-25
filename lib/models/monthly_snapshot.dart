/// Append-only monthly aggregate. One row per month, written on first open of
/// the next month (UNIQUE month+year in SQL). Cheaper than recalculating from
/// raw transactions forever. [savings] and [savingsRate] are computed
/// client-side and stored for query convenience.
class MonthlySnapshot {
  final String? id;
  final int month; // 1–12
  final int year;
  final double income;
  final double expenses;
  final double investments;
  final double savings;
  final double savingsRate;
  final double netWorth;
  final DateTime? recordedAt;

  MonthlySnapshot({
    this.id,
    required this.month,
    required this.year,
    this.income = 0,
    this.expenses = 0,
    this.investments = 0,
    this.savings = 0,
    this.savingsRate = 0,
    this.netWorth = 0,
    this.recordedAt,
  });

  factory MonthlySnapshot.fromJson(Map<String, dynamic> json) {
    return MonthlySnapshot(
      id: json['id'] as String?,
      month: (json['month'] as num).toInt(),
      year: (json['year'] as num).toInt(),
      income: (json['income'] as num?)?.toDouble() ?? 0,
      expenses: (json['expenses'] as num?)?.toDouble() ?? 0,
      investments: (json['investments'] as num?)?.toDouble() ?? 0,
      savings: (json['savings'] as num?)?.toDouble() ?? 0,
      savingsRate: (json['savings_rate'] as num?)?.toDouble() ?? 0,
      netWorth: (json['net_worth'] as num?)?.toDouble() ?? 0,
      recordedAt: json['recorded_at'] != null
          ? DateTime.parse(json['recorded_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'month': month,
      'year': year,
      'income': income,
      'expenses': expenses,
      'investments': investments,
      'savings': savings,
      'savings_rate': savingsRate,
      'net_worth': netWorth,
    };
  }
}
