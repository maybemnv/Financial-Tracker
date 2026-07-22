import 'package:flutter/material.dart';

class TransactionLabel {
  const TransactionLabel({
    this.id,
    required this.name,
    required this.color,
    this.excludeFromPersonalSpend = false,
  });

  final String? id;
  final String name;
  final String color;

  /// When true, debits whose primary label is this label are reported as
  /// **Family Support**, not Personal Spend (PRD §4). Only the `FAMILY` label
  /// carries this flag (enforced in migration `00011` + label management).
  final bool excludeFromPersonalSpend;

  factory TransactionLabel.fromJson(Map<String, dynamic> json) {
    return TransactionLabel(
      id: json['id'] as String?,
      name: json['name'] as String,
      color: json['color'] as String,
      excludeFromPersonalSpend:
          json['exclude_from_personal_spend'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'color': color,
        'exclude_from_personal_spend': excludeFromPersonalSpend,
      };

  TransactionLabel copyWith({
    String? id,
    String? name,
    String? color,
    bool? excludeFromPersonalSpend,
  }) =>
      TransactionLabel(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color ?? this.color,
        excludeFromPersonalSpend:
            excludeFromPersonalSpend ?? this.excludeFromPersonalSpend,
      );

  Color get colorValue {
    final normalized = color.replaceFirst('#', '');
    return Color(int.parse('FF$normalized', radix: 16));
  }
}
