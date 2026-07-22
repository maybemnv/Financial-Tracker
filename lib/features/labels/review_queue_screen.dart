import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../models/transaction.dart';
import '../../models/transaction_label.dart';
import '../../core/ledger_query.dart';
import '../../providers/aggregate_provider.dart';
import '../../providers/label_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/newsprint_primitives.dart';

final _currency =
    NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
final _day = DateFormat('d MMM yyyy');

/// Review queue for expenses whose spend cannot yet be attributed (TODO 5.5).
///
/// Two distinct states, deliberately kept apart:
///  - **Needs primary label** — a multi-label expense with no primary. Its
///    amount is unattributed until one is picked, so this is the actionable one.
///  - **Unlabeled** — no labels at all. Valid and reported as `Unlabeled`;
///    listed so it can be classified, not because anything is broken.
class ReviewQueueScreen extends ConsumerStatefulWidget {
  const ReviewQueueScreen({super.key});

  @override
  ConsumerState<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends ConsumerState<ReviewQueueScreen> {
  bool _showUnlabeled = false;

  @override
  Widget build(BuildContext context) {
    // Server-side buckets. Deriving these from loaded rows would only ever
    // surface unresolved rows inside the current page, and the ones needing
    // review are usually the oldest — precisely what a first page excludes.
    final filter = _showUnlabeled
        ? UnresolvedFilter.unlabeled
        : UnresolvedFilter.needsPrimary;
    final bucket = ref.watch(reviewBucketProvider(filter));
    final summary = ref.watch(briefingSummaryProvider(null));
    final needsPrimaryCount =
        summary.maybeWhen(data: (s) => s.needsPrimaryCount, orElse: () => 0);
    final unlabeledCount =
        summary.maybeWhen(data: (s) => s.unlabeledCount, orElse: () => 0);

    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Review')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text('Needs primary ($needsPrimaryCount)'),
              ),
              ButtonSegment(
                value: true,
                label: Text('Unlabeled ($unlabeledCount)'),
              ),
            ],
            selected: {_showUnlabeled},
            onSelectionChanged: (v) => setState(() => _showUnlabeled = v.first),
          ),
          const SizedBox(height: 8),
          Text(
            _showUnlabeled
                ? 'These expenses carry no labels. They report as Unlabeled, '
                    'which is a valid bucket — classify them when convenient.'
                : 'These expenses carry several labels but none is marked '
                    'primary, so their amount is not attributed to any '
                    'category. Pick the one each counts under.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          ...bucket.when(
            loading: () => const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (e, _) => [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: NewsprintNotice(
                  icon: Icons.error_outline_rounded,
                  title: 'Review queue unavailable',
                  message: e is PostgrestException ? e.message : '$e',
                  color: AppTheme.redAccent,
                ),
              ),
            ],
            data: (rows) => rows.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: NewsprintNotice(
                          icon: Icons.check_circle_outline_rounded,
                          title: _showUnlabeled
                              ? 'All labelled'
                              : 'Nothing to review',
                          message: _showUnlabeled
                              ? 'Every expense carries at least one label.'
                              : 'Every labelled expense has a primary label, '
                                  'so all spend is attributed exactly once.',
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ),
                  ]
                : rows
                    .map((tx) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ReviewRow(transaction: tx),
                        ))
                    .toList(),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends ConsumerStatefulWidget {
  const _ReviewRow({required this.transaction});

  final Transaction transaction;

  @override
  ConsumerState<_ReviewRow> createState() => _ReviewRowState();
}

class _ReviewRowState extends ConsumerState<_ReviewRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final tx = widget.transaction;
    final theme = Theme.of(context);
    final when = tx.transactedAt ?? tx.createdAt;

    return NewsprintPanel(
      color: AppTheme.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tx.merchant ?? tx.note ?? tx.vpa ?? 'Unknown',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(_currency.format(tx.amount),
                  style: theme.textTheme.titleMedium),
            ],
          ),
          if (when != null)
            Text(_day.format(when), style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          if (tx.labels.isEmpty)
            _AssignFromAll(transaction: tx, busy: _busy, onRun: _run)
          else ...[
            Text('Counts under', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in tx.labels)
                  if (label.id != null)
                    ChoiceChip(
                      label: Text(label.name),
                      selected: false,
                      onSelected:
                          _busy ? null : (_) => _assign(label.id!),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _assign(String labelId) => _run(() => ref
      .read(transactionProvider.notifier)
      .update(widget.transaction.copyWith(primaryLabelId: labelId)));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                e is PostgrestException ? e.message : '$e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// An unlabeled expense has nothing to choose from, so classification means
/// attaching a label and making it primary in the same audited write.
class _AssignFromAll extends ConsumerWidget {
  const _AssignFromAll({
    required this.transaction,
    required this.busy,
    required this.onRun,
  });

  final Transaction transaction;
  final bool busy;
  final Future<void> Function(Future<void> Function()) onRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = ref.watch(assignableLabelProvider);
    if (labels.isEmpty) {
      return Text('Create a label first.',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final label in labels)
          if (label.id != null)
            ActionChip(
              label: Text(label.name),
              onPressed: busy
                  ? null
                  : () => onRun(() => _attach(ref, label)),
            ),
      ],
    );
  }

  Future<void> _attach(WidgetRef ref, TransactionLabel label) =>
      ref.read(transactionProvider.notifier).update(
            transaction.copyWith(
              labels: [label],
              primaryLabelId: label.id,
            ),
          );
}
