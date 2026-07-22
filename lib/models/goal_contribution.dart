/// One recorded change to a goal's earmarked total. Corrections are new
/// negative rows — an existing row is never edited or removed, so the history
/// always reconciles with `goals.allocated_amount`.
class GoalContribution {
  final String id;
  final String goalId;
  final double amount;
  final String? note;
  final DateTime createdAt;

  const GoalContribution({
    required this.id,
    required this.goalId,
    required this.amount,
    required this.createdAt,
    this.note,
  });

  /// A negative row: a correction, a removal, or the outgoing leg of a
  /// reallocation.
  bool get isCorrection => amount < 0;

  factory GoalContribution.fromJson(Map<String, dynamic> json) {
    return GoalContribution(
      id: json['id'] as String,
      goalId: json['goal_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
