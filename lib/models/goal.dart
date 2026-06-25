/// A savings goal. [type] (not the name) drives dashboard/agent behaviour —
/// `emergency_fund` is detected by type so the goal can be renamed freely.
class Goal {
  final String? id;
  final String name;
  final String type; // emergency_fund | custom
  final double targetAmount;
  final double allocatedAmount;
  final bool isDeleted;
  final DateTime? deletedAt;
  final DateTime? createdAt;

  Goal({
    this.id,
    required this.name,
    this.type = 'custom',
    required this.targetAmount,
    this.allocatedAmount = 0,
    this.isDeleted = false,
    this.deletedAt,
    this.createdAt,
  });

  bool get isEmergencyFund => type == 'emergency_fund';

  double get fundedPercent {
    if (targetAmount == 0) return 0;
    return (allocatedAmount / targetAmount) * 100;
  }

  factory Goal.fromJson(Map<String, dynamic> json) {
    return Goal(
      id: json['id'] as String?,
      name: json['name'] as String,
      type: json['type'] as String? ?? 'custom',
      targetAmount: (json['target_amount'] as num).toDouble(),
      allocatedAmount: (json['allocated_amount'] as num?)?.toDouble() ?? 0,
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
      'target_amount': targetAmount,
      'allocated_amount': allocatedAmount,
    };
  }
}
