import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Short-lived UI draft persistence (Phase 11.5).
///
/// Survives an installed-PWA resume or reload so a half-typed transaction is
/// not lost, without ever persisting anything sensitive. Guarantees enforced on
/// every read:
///   * schema version must match — an incompatible draft is dropped, never
///     coerced;
///   * owner id must match the current session — a draft from another account
///     is never restored;
///   * 24-hour expiry — a stale draft is discarded.
///
/// It deliberately holds only what the owner explicitly typed. No auth token,
/// no balances, no fetched financial context — see [TransactionDraft].
class DraftStore {
  DraftStore(this._prefs);

  final SharedPreferences _prefs;

  static const int schemaVersion = 1;
  static const Duration ttl = Duration(hours: 24);

  static Future<DraftStore> open() async =>
      DraftStore(await SharedPreferences.getInstance());

  /// Namespaced by draft kind, so a form draft and the active-tab draft do not
  /// collide.
  String _key(String kind) => 'draft.$kind';

  void save(String kind, String ownerId, Map<String, Object?> data) {
    final envelope = {
      'v': schemaVersion,
      'owner': ownerId,
      'saved_at': DateTime.now().toIso8601String(),
      'data': data,
    };
    _prefs.setString(_key(kind), jsonEncode(envelope));
  }

  /// Returns the stored payload only if it is current-version, owned by
  /// [ownerId], and within [ttl]. Anything else is dropped and cleared so a bad
  /// record cannot linger.
  Map<String, Object?>? load(String kind, String ownerId) {
    final raw = _prefs.getString(_key(kind));
    if (raw == null) return null;
    try {
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      if (envelope['v'] != schemaVersion) return _drop(kind);
      if (envelope['owner'] != ownerId) return _drop(kind);

      final savedAt = DateTime.tryParse(envelope['saved_at'] as String? ?? '');
      if (savedAt == null || DateTime.now().difference(savedAt) > ttl) {
        return _drop(kind);
      }
      final data = envelope['data'];
      if (data is! Map) return _drop(kind);
      return Map<String, Object?>.from(data);
    } catch (_) {
      // Malformed JSON: discard rather than risk a partial restore.
      return _drop(kind);
    }
  }

  Map<String, Object?>? _drop(String kind) {
    clear(kind);
    return null;
  }

  void clear(String kind) => _prefs.remove(_key(kind));

  /// Wipe every draft — used on sign-out so the next owner starts clean.
  void clearAll() {
    for (final key in _prefs.getKeys()) {
      if (key.startsWith('draft.')) _prefs.remove(key);
    }
  }
}

/// The transaction-form draft. Explicitly typed so it is obvious that only
/// owner-entered fields are persisted — no token, no fetched money data.
class TransactionDraft {
  const TransactionDraft({
    this.amount,
    this.type,
    this.accountId,
    this.merchant,
    this.note,
    this.labelIds = const [],
    this.primaryLabelId,
  });

  final String? amount;
  final String? type;
  final String? accountId;
  final String? merchant;
  final String? note;
  final List<String> labelIds;
  final String? primaryLabelId;

  bool get isEmpty =>
      (amount == null || amount!.isEmpty) &&
      (merchant == null || merchant!.isEmpty) &&
      (note == null || note!.isEmpty) &&
      labelIds.isEmpty;

  Map<String, Object?> toJson() => {
        'amount': amount,
        'type': type,
        'account_id': accountId,
        'merchant': merchant,
        'note': note,
        'label_ids': labelIds,
        'primary_label_id': primaryLabelId,
      };

  factory TransactionDraft.fromJson(Map<String, Object?> j) => TransactionDraft(
        amount: j['amount'] as String?,
        type: j['type'] as String?,
        accountId: j['account_id'] as String?,
        merchant: j['merchant'] as String?,
        note: j['note'] as String?,
        labelIds: (j['label_ids'] as List?)?.cast<String>() ?? const [],
        primaryLabelId: j['primary_label_id'] as String?,
      );
}
