import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/aggregates.dart';
import '../../core/label_usage.dart';
import '../../core/theme.dart';
import '../../models/transaction_label.dart';
import '../../providers/aggregate_provider.dart';
import '../../providers/label_provider.dart';
import '../../widgets/newsprint_primitives.dart';

final _currency =
    NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');

/// Label lifecycle management (TODO 5.11). Every action routes through an
/// owner-scoped RPC in `00013`, each of which writes exactly one `label_audit`
/// entry. Nothing here is a direct table write.
class LabelManagementScreen extends ConsumerStatefulWidget {
  const LabelManagementScreen({super.key});

  @override
  ConsumerState<LabelManagementScreen> createState() =>
      _LabelManagementScreenState();
}

class _LabelManagementScreenState
    extends ConsumerState<LabelManagementScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final labelsAsync = ref.watch(labelProvider);
    // Whole-ledger counts. Deriving these from loaded rows would understate
    // what a rename or merge affects now that the ledger is paged.
    final usageAsync = ref.watch(labelUsageStatsProvider);

    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Labels')),
      body: labelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: NewsprintNotice(
            icon: Icons.error_outline_rounded,
            title: 'Labels unavailable',
            message: _errorText(e),
            color: AppTheme.redAccent,
          ),
        ),
        data: (labels) {
          final active = labels.where((l) => l.isActive).toList();
          final archived = labels.where((l) => l.isArchived).toList();
          final shown = _showArchived ? archived : active;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                      value: false, label: Text('Active (${active.length})')),
                  ButtonSegment(
                      value: true, label: Text('Archived (${archived.length})')),
                ],
                selected: {_showArchived},
                onSelectionChanged: (v) =>
                    setState(() => _showArchived = v.first),
              ),
              const SizedBox(height: 8),
              Text(
                _showArchived
                    ? 'Archived labels stay attached to past transactions and '
                        'keep reporting, but cannot be added to new ones.'
                    : 'Renaming keeps a label\'s identity, so every past '
                        'transaction follows the new name.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    _showArchived
                        ? 'No archived labels.'
                        : 'No labels yet. Create one from the transaction form.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                ...shown.map((label) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LabelRow(
                        label: label,
                        // null = not counted yet. Never defaulted to zero:
                        // that would read as "unreferenced" and offer DELETE
                        // on a label the whole ledger depends on.
                        usage: usageAsync.valueOrNull?[label.id],
                        allLabels: labels,
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class _LabelRow extends ConsumerStatefulWidget {
  const _LabelRow({
    required this.label,
    required this.usage,
    required this.allLabels,
  });

  final TransactionLabel label;

  /// Whole-ledger usage, or null while it is still being counted.
  final LabelUsageStat? usage;
  final List<TransactionLabel> allLabels;

  @override
  ConsumerState<_LabelRow> createState() => _LabelRowState();
}

class _LabelRowState extends ConsumerState<_LabelRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final usage = widget.usage;
    final theme = Theme.of(context);

    return NewsprintPanel(
      color: AppTheme.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: label.colorValue,
                  border: Border.all(color: AppTheme.ink, width: 1.5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label.name, style: theme.textTheme.titleMedium),
              ),
              if (label.excludeFromPersonalSpend)
                const NewsprintTag(label: 'Family support'),
            ],
          ),
          const SizedBox(height: 8),
          Text(_usageSummary(usage), style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (label.isActive) ...[
                OutlinedButton(
                  onPressed: _busy ? null : _rename,
                  child: const Text('RENAME'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _merge,
                  child: const Text('MERGE'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _setStatus('archived'),
                  child: const Text('ARCHIVE'),
                ),
              ] else
                OutlinedButton(
                  onPressed: _busy ? null : () => _setStatus('active'),
                  child: const Text('RESTORE'),
                ),
              // Only once usage is known: delete_label raises for a
              // referenced label, and offering it blind invites the error.
              if (usage != null && usage.isUnreferenced)
                TextButton(
                  onPressed: _busy ? null : _delete,
                  child: const Text('DELETE'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _usageSummary(LabelUsageStat? usage) {
    if (usage == null) return 'Counting usage…';
    if (usage.isUnreferenced) {
      return 'Not used by any transaction — safe to delete.';
    }
    final parts = <String>[
      'On ${usage.attachedCount} transaction${usage.attachedCount == 1 ? '' : 's'}',
    ];
    if (usage.primaryCount > 0) {
      parts.add('${usage.primaryCount} count under it '
          '(${_currency.format(usage.attributedAmount)})');
    }
    if (usage.contextualCount > 0) {
      parts.add('${usage.contextualCount} contextual only');
    }
    return parts.join(' · ');
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: widget.label.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 10),
            Text(
              'The label keeps its identity, so all '
              '${widget.usage?.attachedCount ?? 0} existing transactions follow '
              'the new name. Nothing is re-categorised.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('RENAME'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == widget.label.name) return;
    // The controller text is kept on failure so a name clash can be corrected
    // without retyping (TODO 5.11 "preserve form state on recoverable errors").
    await _run(() =>
        ref.read(labelProvider.notifier).rename(widget.label.id!, name));
  }

  Future<void> _merge() async {
    final targets = mergeTargetsFor(widget.label, widget.allLabels);
    if (targets.isEmpty) {
      _message('There is no other active label to merge into.');
      return;
    }

    final targetId = await showDialog<String>(
      context: context,
      builder: (ctx) => _MergeDialog(source: widget.label, targets: targets),
    );
    if (targetId == null) return;

    final target = targets.firstWhere((t) => t.id == targetId);
    final ok = await _confirm(
      title: 'Merge into ${target.name}?',
      message:
          'All ${widget.usage?.attachedCount ?? 0} transactions on "${widget.label.name}" '
          'move to "${target.name}", including the ${widget.usage?.primaryCount ?? 0} '
          'that count under it (${_currency.format(widget.usage?.attributedAmount ?? 0)}). '
          '"${widget.label.name}" is then marked merged. This cannot be undone.',
      confirmLabel: 'MERGE',
    );
    if (!ok) return;

    await _run(() => ref
        .read(labelProvider.notifier)
        .merge(sourceId: widget.label.id!, targetId: targetId));
  }

  Future<void> _setStatus(String status) async {
    if (status == 'archived') {
      final ok = await _confirm(
        title: 'Archive ${widget.label.name}?',
        message:
            'It stops appearing when labelling new transactions. The '
            '${widget.usage?.attachedCount ?? 0} that already use it keep it, and '
            'reports are unchanged. You can restore it later.',
        confirmLabel: 'ARCHIVE',
      );
      if (!ok) return;
    }
    await _run(() =>
        ref.read(labelProvider.notifier).setStatus(widget.label.id!, status));
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      title: 'Delete ${widget.label.name}?',
      message: 'No transaction uses this label, so nothing is re-categorised. '
          'A label that is in use must be archived or merged instead.',
      confirmLabel: 'DELETE',
    );
    if (!ok) return;
    await _run(() => ref.read(labelProvider.notifier).delete(widget.label.id!));
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(message),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _message(_errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }
}

class _MergeDialog extends StatefulWidget {
  const _MergeDialog({required this.source, required this.targets});

  final TransactionLabel source;
  final List<TransactionLabel> targets;

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  String? _targetId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Merge ${widget.source.name}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose the label to keep. Archived and merged labels are not '
              'offered — a merge target must be assignable.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _targetId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Merge into *'),
              items: widget.targets
                  .map((l) => DropdownMenuItem(
                        value: l.id,
                        child: Text(l.name, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _targetId = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL')),
        FilledButton(
          onPressed:
              _targetId == null ? null : () => Navigator.pop(context, _targetId),
          child: const Text('CONTINUE'),
        ),
      ],
    );
  }
}

String _errorText(Object error) =>
    error is PostgrestException ? error.message : '$error';
