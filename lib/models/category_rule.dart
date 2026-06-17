class CategoryRule {
  final String? id;
  final String matchPattern;
  final String category;
  final List<String> tags;
  final int priority;

  CategoryRule({
    this.id,
    required this.matchPattern,
    required this.category,
    this.tags = const [],
    this.priority = 0,
  });

  factory CategoryRule.fromJson(Map<String, dynamic> json) {
    return CategoryRule(
      id: json['id'] as String?,
      matchPattern: json['match_pattern'] as String,
      category: json['category'] as String,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      priority: (json['priority'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'match_pattern': matchPattern,
      'category': category,
      'tags': tags,
      'priority': priority,
    };
  }
}
