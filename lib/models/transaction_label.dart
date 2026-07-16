import 'package:flutter/material.dart';

class TransactionLabel {
  const TransactionLabel({
    this.id,
    required this.name,
    required this.color,
  });

  final String? id;
  final String name;
  final String color;

  factory TransactionLabel.fromJson(Map<String, dynamic> json) {
    return TransactionLabel(
      id: json['id'] as String?,
      name: json['name'] as String,
      color: json['color'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'color': color,
      };

  Color get colorValue {
    final normalized = color.replaceFirst('#', '');
    return Color(int.parse('FF$normalized', radix: 16));
  }
}
