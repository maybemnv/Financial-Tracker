/// A read-time merchant normalization rule (Phase 10.2). The raw merchant on
/// each transaction is never touched; an alias only changes how rows roll up.
class MerchantAlias {
  const MerchantAlias({
    this.id,
    required this.matchPattern,
    required this.canonicalName,
    this.createdAt,
  });

  final String? id;

  /// Case-insensitive substring matched against the raw merchant.
  final String matchPattern;
  final String canonicalName;
  final DateTime? createdAt;

  factory MerchantAlias.fromJson(Map<String, dynamic> json) => MerchantAlias(
        id: json['id'] as String?,
        matchPattern: json['match_pattern'] as String,
        canonicalName: json['canonical_name'] as String,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'match_pattern': matchPattern.trim(),
        'canonical_name': canonicalName.trim(),
      };
}

/// Canonicalises a raw merchant name against a set of aliases. Longest pattern
/// wins, matching `app_canonical_merchant` in SQL so read-time UI normalization
/// and server analytics agree.
String canonicalMerchant(String? raw, Iterable<MerchantAlias> aliases) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return 'Unknown';
  final lower = trimmed.toLowerCase();

  MerchantAlias? best;
  for (final alias in aliases) {
    if (lower.contains(alias.matchPattern.toLowerCase())) {
      if (best == null ||
          alias.matchPattern.length > best.matchPattern.length) {
        best = alias;
      }
    }
  }
  return best?.canonicalName ?? trimmed;
}
