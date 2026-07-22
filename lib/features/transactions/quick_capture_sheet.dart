import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/quick_capture.dart';
import '../../core/theme.dart';
import '../../models/account.dart';
import '../../models/transaction.dart';
import '../../providers/account_provider.dart';
import '../../providers/label_provider.dart';
import '../../providers/transaction_provider.dart';

final _currency =
    NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');

/// One-field quick capture (TODO 10.1). Type `250 biryani cash`, review the
/// parsed draft, confirm. Parsing is deterministic and local; the confirmed
/// save goes through the same audited `save_transaction_with_labels` path as
/// the full form, so no validation is skipped.
class QuickCaptureSheet extends ConsumerStatefulWidget {
  const QuickCaptureSheet({super.key});

  @override
  ConsumerState<QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends ConsumerState<QuickCaptureSheet> {
  final _controller = TextEditingController();
  CaptureDraft? _draft;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse() {
    final accounts = ref.read(accountProvider).valueOrNull ?? const <Account>[];
    final labels = ref.read(assignableLabelProvider);
    final parser = QuickCaptureParser(accounts: accounts, labels: labels);
    setState(() => _draft = parser.parse(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick capture',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'e.g. "250 biryani cash" or "500 sent to mummy kotak". '
            'You confirm before anything saves.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'What happened',
              hintText: '250 biryani cash',
            ),
            onChanged: (_) => _parse(),
            onSubmitted: (_) => _parse(),
          ),
          if (_draft != null) ...[
            const SizedBox(height: 16),
            _DraftPreview(
              draft: _draft!,
              onChanged: (d) => setState(() => _draft = d),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              const Spacer(),
              FilledButton(
                onPressed:
                    (_draft?.isComplete ?? false) && !_saving ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('SAVE'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final draft = _draft!;
    // A labelled expense must name a primary; the parser only ever sets one
    // label, so this is satisfied whenever a label was matched.
    setState(() => _saving = true);
    try {
      final ok = await ref.read(transactionProvider.notifier).add(
            Transaction(
              amount: draft.amount!,
              type: draft.type,
              direction: draft.isExpense ? 'outflow' : 'inflow',
              accountId: draft.accountId,
              merchant: draft.merchant,
              primaryLabelId: draft.primaryLabelId,
              labels: draft.primaryLabelId == null
                  ? const []
                  : [
                      ref
                          .read(assignableLabelProvider)
                          .firstWhere((l) => l.id == draft.primaryLabelId)
                    ],
              source: 'manual',
              transactedAt: DateTime.now(),
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Looks like a duplicate — not saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }
}

class _DraftPreview extends ConsumerWidget {
  const _DraftPreview({required this.draft, required this.onChanged});

  final CaptureDraft draft;
  final ValueChanged<CaptureDraft> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountProvider).valueOrNull ?? const <Account>[];
    final labels = ref.watch(assignableLabelProvider);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration:
          AppTheme.panelDecoration(color: AppTheme.paper, accentTop: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                draft.amount == null
                    ? 'Amount?'
                    : '${draft.isExpense ? '−' : '+'}'
                        '${_currency.format(draft.amount)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'debit', label: Text('Out')),
                  ButtonSegment(value: 'credit', label: Text('In')),
                ],
                selected: {draft.type},
                onSelectionChanged: (v) =>
                    onChanged(draft.copyWith(type: v.first)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: draft.accountId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Account *'),
            items: [
              for (final a in accounts)
                if (a.id != null)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => onChanged(draft.copyWith(accountId: v)),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: draft.primaryLabelId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Label (counts under)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('No label')),
              for (final l in labels)
                if (l.id != null)
                  DropdownMenuItem(value: l.id, child: Text(l.name)),
            ],
            onChanged: (v) => onChanged(draft.copyWith(primaryLabelId: v)),
          ),
          if (draft.merchant != null) ...[
            const SizedBox(height: 8),
            Text('Note: ${draft.merchant}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          for (final w in draft.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: AppTheme.accentGold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(w,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: AppTheme.accentGold)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

