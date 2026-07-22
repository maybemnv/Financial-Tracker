import '../models/transaction.dart';

/// Which unresolved-review bucket the ledger is filtered to (TODO 5.5 / 7.1).
enum UnresolvedFilter {
  none,

  /// Multi-label expenses with no primary — amount attributed to nothing.
  needsPrimary,

  /// Expenses with no labels at all.
  unlabeled;

  String? get wireValue => switch (this) {
        UnresolvedFilter.none => null,
        UnresolvedFilter.needsPrimary => 'needs_primary',
        UnresolvedFilter.unlabeled => 'unlabeled',
      };
}

/// Everything that narrows a ledger page. Immutable and value-equal so a
/// provider can reset its pages when — and only when — the query changes.
class LedgerQuery {
  const LedgerQuery({
    this.accountId,
    this.labelId,
    this.type,
    this.search,
    this.from,
    this.to,
    this.unresolved = UnresolvedFilter.none,
  });

  final String? accountId;
  final String? labelId;
  final String? type;
  final String? search;
  final DateTime? from;
  final DateTime? to;
  final UnresolvedFilter unresolved;

  LedgerQuery copyWith({
    String? accountId,
    String? labelId,
    String? type,
    String? search,
    DateTime? from,
    DateTime? to,
    UnresolvedFilter? unresolved,
    bool clearAccount = false,
    bool clearLabel = false,
    bool clearType = false,
    bool clearSearch = false,
    bool clearRange = false,
  }) =>
      LedgerQuery(
        accountId: clearAccount ? null : (accountId ?? this.accountId),
        labelId: clearLabel ? null : (labelId ?? this.labelId),
        type: clearType ? null : (type ?? this.type),
        search: clearSearch ? null : (search ?? this.search),
        from: clearRange ? null : (from ?? this.from),
        to: clearRange ? null : (to ?? this.to),
        unresolved: unresolved ?? this.unresolved,
      );

  Map<String, dynamic> toParams({
    required int limit,
    LedgerCursor? cursor,
  }) =>
      {
        'p_limit': limit,
        'p_cursor_at': cursor?.effectiveAt.toIso8601String(),
        'p_cursor_id': cursor?.id,
        'p_account_id': accountId,
        'p_label_id': labelId,
        'p_type': type,
        'p_search': (search == null || search!.trim().isEmpty) ? null : search!.trim(),
        'p_from': from?.toIso8601String().split('T').first,
        'p_to': to?.toIso8601String().split('T').first,
        'p_unresolved': unresolved.wireValue,
      };

  @override
  bool operator ==(Object other) =>
      other is LedgerQuery &&
      other.accountId == accountId &&
      other.labelId == labelId &&
      other.type == type &&
      other.search == search &&
      other.from == from &&
      other.to == to &&
      other.unresolved == unresolved;

  @override
  int get hashCode =>
      Object.hash(accountId, labelId, type, search, from, to, unresolved);

  /// Whether a row still belongs in this page set after an edit or a Realtime
  /// event. Used to decide replace-in-place vs remove, so a changed row is
  /// never left sorted into the wrong position (TODO 7.2).
  ///
  /// Deliberately conservative: it can only rule a row *out* on the filters it
  /// can evaluate locally. Anything it cannot judge stays, and the next refresh
  /// reconciles.
  bool matches(Transaction t) {
    if (t.isDeleted) return false;
    if (accountId != null && t.accountId != accountId) return false;
    if (type != null && t.type != type) return false;
    if (labelId != null && !t.labels.any((l) => l.id == labelId)) return false;

    final at = t.transactedAt ?? t.createdAt;
    if (at != null) {
      if (from != null && at.isBefore(from!)) return false;
      if (to != null && at.isAfter(to!.add(const Duration(days: 1)))) return false;
    }

    final term = search?.trim().toLowerCase();
    if (term != null && term.isNotEmpty) {
      final haystack =
          '${t.merchant ?? ''} ${t.note ?? ''} ${t.vpa ?? ''}'.toLowerCase();
      if (!haystack.contains(term)) return false;
    }
    return true;
  }
}

/// Keyset cursor: the last row's effective timestamp and id. Ordering is
/// `(effective_at DESC, id DESC)`, and the id tiebreak is what makes equal
/// timestamps page deterministically instead of repeating or skipping rows.
class LedgerCursor {
  const LedgerCursor({required this.effectiveAt, required this.id});

  final DateTime effectiveAt;
  final String id;

  static LedgerCursor? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final at = json['at'] as String?;
    final id = json['id'] as String?;
    if (at == null || id == null) return null;
    return LedgerCursor(effectiveAt: DateTime.parse(at), id: id);
  }

  @override
  bool operator ==(Object other) =>
      other is LedgerCursor && other.effectiveAt == effectiveAt && other.id == id;

  @override
  int get hashCode => Object.hash(effectiveAt, id);
}

/// One page of ledger rows plus the cursor that continues it.
class LedgerPage {
  const LedgerPage({
    required this.rows,
    required this.hasMore,
    this.nextCursor,
  });

  final List<Transaction> rows;
  final bool hasMore;
  final LedgerCursor? nextCursor;

  static const int supportedVersion = 1;

  /// Parses the versioned RPC envelope. An unknown version throws rather than
  /// silently reading nulls out of a shape this build does not understand.
  factory LedgerPage.fromRpc(Map<String, dynamic> json) {
    final version = (json['version'] as num?)?.toInt();
    if (version != supportedVersion) {
      throw FormatException(
        'Ledger page version $version is not supported by this build '
        '(expected $supportedVersion). Update the app.',
      );
    }
    final rows = (json['rows'] as List? ?? const [])
        .map((r) => Transaction.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
    return LedgerPage(
      rows: rows,
      hasMore: json['has_more'] as bool? ?? false,
      nextCursor: LedgerCursor.fromJson(
        json['next_cursor'] == null
            ? null
            : Map<String, dynamic>.from(json['next_cursor'] as Map),
      ),
    );
  }
}

/// Accumulated ledger state across loaded pages.
class LedgerState {
  const LedgerState({
    this.rows = const [],
    this.query = const LedgerQuery(),
    this.cursor,
    this.hasMore = true,
    this.isLoadingFirstPage = true,
    this.isLoadingMore = false,
    this.error,
    this.pageError,
  });

  final List<Transaction> rows;
  final LedgerQuery query;
  final LedgerCursor? cursor;
  final bool hasMore;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;

  /// Fatal for the list — nothing is displayable.
  final Object? error;

  /// A next-page failure. Visible rows are kept and a retry is offered, so a
  /// flaky scroll never blanks the ledger (TODO 7.2).
  final Object? pageError;

  bool get isEmpty => rows.isEmpty && !isLoadingFirstPage && error == null;

  LedgerState copyWith({
    List<Transaction>? rows,
    LedgerQuery? query,
    LedgerCursor? cursor,
    bool? hasMore,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    Object? error,
    Object? pageError,
    bool clearCursor = false,
    bool clearError = false,
    bool clearPageError = false,
  }) =>
      LedgerState(
        rows: rows ?? this.rows,
        query: query ?? this.query,
        cursor: clearCursor ? null : (cursor ?? this.cursor),
        hasMore: hasMore ?? this.hasMore,
        isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        error: clearError ? null : (error ?? this.error),
        pageError: clearPageError ? null : (pageError ?? this.pageError),
      );
}
