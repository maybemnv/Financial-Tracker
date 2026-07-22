import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/ledger_query.dart';
import '../core/supabase.dart';
import '../models/transaction.dart';

/// Server-paged ledger (Phase 7, fixes D4).
///
/// Replaces the full-table read: the ledger now fetches one bounded page at a
/// time through `get_transaction_page`, filters server-side against indexes,
/// and patches individual rows on Realtime events instead of reloading
/// everything on every change.
class LedgerNotifier extends StateNotifier<LedgerState> {
  LedgerNotifier() : super(const LedgerState());

  static const int pageSize = 50;

  RealtimeChannel? _channel;
  Timer? _debounce;

  /// Guards against overlapping page requests — a fast scroll must not issue
  /// the same next-page call twice and append duplicates.
  bool _fetching = false;

  /// Incremented on every query change; a slow in-flight response for a stale
  /// query is discarded instead of being appended to the new result set.
  int _generation = 0;

  Future<void> loadFirstPage() async {
    final generation = ++_generation;
    state = state.copyWith(
      isLoadingFirstPage: true,
      clearError: true,
      clearPageError: true,
    );
    try {
      final page = await _fetch(cursor: null);
      if (generation != _generation) return;
      state = state.copyWith(
        rows: page.rows,
        cursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingFirstPage: false,
        clearCursor: page.nextCursor == null,
      );
    } catch (e) {
      if (generation != _generation) return;
      state = state.copyWith(isLoadingFirstPage: false, error: e);
    }
  }

  /// Appends the next page. Safe to call repeatedly from a scroll listener.
  Future<void> loadMore() async {
    if (_fetching || !state.hasMore || state.isLoadingFirstPage) return;
    final cursor = state.cursor;
    if (cursor == null) return;

    _fetching = true;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearPageError: true);
    try {
      final page = await _fetch(cursor: cursor);
      if (generation != _generation) return;
      // De-duplicate defensively: a row inserted above the cursor between
      // pages must not appear twice if it also arrives via Realtime.
      final seen = state.rows.map((r) => r.id).toSet();
      final fresh = page.rows.where((r) => !seen.contains(r.id));
      state = state.copyWith(
        rows: [...state.rows, ...fresh],
        cursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingMore: false,
      );
    } catch (e) {
      if (generation != _generation) return;
      // Keep the rows already on screen; surface a localized retry instead.
      state = state.copyWith(isLoadingMore: false, pageError: e);
    } finally {
      _fetching = false;
    }
  }

  /// Applies a new filter set and reloads from page one. Cursor and pages reset
  /// atomically so a stale cursor can never be applied to a new query.
  Future<void> setQuery(LedgerQuery query) async {
    if (query == state.query) return;
    state = state.copyWith(
      query: query,
      rows: const [],
      hasMore: true,
      clearCursor: true,
      clearError: true,
      clearPageError: true,
    );
    await loadFirstPage();
  }

  Future<void> refresh() => loadFirstPage();

  Future<LedgerPage> _fetch({required LedgerCursor? cursor}) async {
    final result = await SupabaseService().client.rpc(
          'get_transaction_page',
          params: state.query.toParams(limit: pageSize, cursor: cursor),
        );
    return LedgerPage.fromRpc(Map<String, dynamic>.from(result as Map));
  }

  // --- Realtime -------------------------------------------------------------

  void subscribe() {
    _channel = SupabaseService()
        .client
        .channel('ledger')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          table: 'transactions',
          callback: _onTransactionChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          table: 'transaction_labels',
          // A join change carries no transaction fields, so the row's current
          // labels are unknowable from the event alone — refresh the first
          // page rather than patch from incomplete data.
          callback: (_) => _debouncedRefresh(),
        )
        .subscribe();
  }

  void _onTransactionChange(PostgresChangePayload payload) {
    final record = payload.newRecord;
    final oldId = payload.oldRecord['id'] as String?;

    // Deletes (soft or physical) only ever remove a row we may be showing.
    if (payload.eventType == PostgresChangeEvent.delete) {
      if (oldId != null) _removeRow(oldId);
      return;
    }
    if (record.isEmpty) {
      _debouncedRefresh();
      return;
    }

    final id = record['id'] as String?;
    if (id == null) return;

    final isDeleted = record['is_deleted'] as bool? ?? false;
    if (isDeleted) {
      _removeRow(id);
      return;
    }

    final index = state.rows.indexWhere((r) => r.id == id);
    if (index == -1) {
      // A row we are not showing. It may belong at the top of the current
      // page set, but the event has no label data, so let a debounced refresh
      // place it correctly rather than guessing.
      _debouncedRefresh();
      return;
    }

    // An update to a row already on screen: patch it, preserving the labels the
    // page query supplied (the event does not carry them). If the edit pushed
    // it out of the active filter, drop it instead of leaving it mis-sorted.
    final existing = state.rows[index];
    final patched = _merge(existing, record);
    if (!state.query.matches(patched)) {
      _removeRow(id);
      return;
    }
    if (_reordered(existing, patched)) {
      _debouncedRefresh();
      return;
    }
    final rows = [...state.rows]..[index] = patched;
    state = state.copyWith(rows: rows);
  }

  /// Applies changed scalar fields from a Realtime record onto a loaded row,
  /// keeping the joined label data the event cannot provide.
  Transaction _merge(Transaction existing, Map<String, dynamic> record) {
    final merged = Map<String, dynamic>.from(record);
    merged['transaction_labels'] = null; // never present on a base-row event
    final parsed = Transaction.fromJson(merged);
    return parsed.copyWith(labels: existing.labels);
  }

  /// True when the edit changes where the row sorts, which page-local patching
  /// cannot express.
  bool _reordered(Transaction before, Transaction after) {
    final a = before.transactedAt ?? before.createdAt;
    final b = after.transactedAt ?? after.createdAt;
    return a != b;
  }

  void _removeRow(String id) {
    if (!state.rows.any((r) => r.id == id)) return;
    state = state.copyWith(
      rows: state.rows.where((r) => r.id != id).toList(growable: false),
    );
  }

  /// Collapses event bursts (a multi-row write emits several) into one refresh.
  void _debouncedRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) loadFirstPage();
    });
  }

  void unsubscribe() {
    _debounce?.cancel();
    _channel?.unsubscribe();
    _channel = null;
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}

final ledgerProvider =
    StateNotifierProvider<LedgerNotifier, LedgerState>((ref) {
  final notifier = LedgerNotifier();
  notifier.loadFirstPage();
  notifier.subscribe();
  ref.onDispose(notifier.unsubscribe);
  return notifier;
});
