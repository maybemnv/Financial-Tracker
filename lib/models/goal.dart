/// A savings goal. [type] (not the name) drives dashboard/agent behaviour —
/// `emergency_fund` is detected by type so the goal can be renamed freely.
class Goal {
  final String? id;
  final String name;
  final String type; // emergency_fund | custom
  final double targetAmount;
  final double allocatedAmount;
  final String status; // active | paused | completed | archived
  final DateTime? targetDate;
  final bool isDeleted;
  final DateTime? deletedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Goal({
    this.id,
    required this.name,
    this.type = 'custom',
    required this.targetAmount,
    this.allocatedAmount = 0,
    this.status = 'active',
    this.targetDate,
    this.isDeleted = false,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  bool get isEmergencyFund => type == 'emergency_fund';
  bool get isActive => status == 'active';
  bool get isArchived => status == 'archived';

  double get fundedPercent {
    if (targetAmount == 0) return 0;
    return (allocatedAmount / targetAmount) * 100;
  }

  double get remaining =>
      (targetAmount - allocatedAmount) <= 0 ? 0 : targetAmount - allocatedAmount;

  factory Goal.fromJson(Map<String, dynamic> json) {
    return Goal(
      id: json['id'] as String?,
      name: json['name'] as String,
      type: json['type'] as String? ?? 'custom',
      targetAmount: (json['target_amount'] as num).toDouble(),
      allocatedAmount: (json['allocated_amount'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'active',
      targetDate: json['target_date'] != null
          ? DateTime.parse(json['target_date'] as String)
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
      'name': name,
      'type': type,
      'target_amount': targetAmount,
      'allocated_amount': allocatedAmount,
      'status': status,
      if (targetDate != null)
        'target_date': targetDate!.toIso8601String().split('T').first,
    };
  }

  Goal copyWith({
    String? id,
    String? name,
    String? type,
    double? targetAmount,
    double? allocatedAmount,
    String? status,
    DateTime? targetDate,
    bool? isDeleted,
    DateTime? deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Goal(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        targetAmount: targetAmount ?? this.targetAmount,
        allocatedAmount: allocatedAmount ?? this.allocatedAmount,
        status: status ?? this.status,
        targetDate: targetDate ?? this.targetDate,
        isDeleted: isDeleted ?? this.isDeleted,
        deletedAt: deletedAt ?? this.deletedAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
