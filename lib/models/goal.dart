class Goal {
  final String? id;
  final String name;
  final double targetAmount;
  final double allocatedAmount;
  final DateTime? createdAt;

  Goal({
    this.id,
    required this.name,
    required this.targetAmount,
    this.allocatedAmount = 0,
    this.createdAt,
  });

  double get fundedPercent {
    if (targetAmount == 0) return 0;
    return (allocatedAmount / targetAmount) * 100;
  }

  factory Goal.fromJson(Map<String, dynamic> json) {
    return Goal(
      id: json['id'] as String?,
      name: json['name'] as String,
      targetAmount: (json['target_amount'] as num).toDouble(),
      allocatedAmount: (json['allocated_amount'] as num?)?.toDouble() ?? 0,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'target_amount': targetAmount,
      'allocated_amount': allocatedAmount,
    };
  }
}
