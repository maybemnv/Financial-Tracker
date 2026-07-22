import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/merchant_alias.dart';
import '../../providers/merchant_alias_provider.dart';

/// Merchant alias management (TODO 10.2) — a section, not a screen. Aliases roll
/// several raw spellings up to one canonical name in analytics; the raw
/// merchant on each transaction is never touched, so the audit trail stands.
class MerchantAliasSheet extends ConsumerStatefulWidget {
  const MerchantAliasSheet({super.key});

  @override
  ConsumerState<MerchantAliasSheet> createState() => _MerchantAliasSheetState();
}

class _MerchantAliasSheetState extends ConsumerState<MerchantAliasSheet> {
  final _patternCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _patternCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aliasesAsync = ref.watch(merchantAliasProvider);

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
          Text('Merchant aliases',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Roll variants up to one name in analytics. A transaction keeps its '
            'raw merchant — aliases never change the record or any amount.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _patternCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Contains',
                    hintText: 'amzn',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Show as',
                    hintText: 'Amazon',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _saving ? null : _add,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: aliasesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Aliases unavailable: $e',
                  style: Theme.of(context).textTheme.bodySmall),
              data: (aliases) => aliases.isEmpty
                  ? Text('No aliases yet.',
                      style: Theme.of(context).textTheme.bodySmall)
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final a in aliases) _AliasRow(alias: a),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final pattern = _patternCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (pattern.isEmpty || name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(merchantAliasProvider.notifier)
          .add(matchPattern: pattern, canonicalName: name);
      _patternCtrl.clear();
      _nameCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AliasRow extends ConsumerWidget {
  const _AliasRow({required this.alias});

  final MerchantAlias alias;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '“${alias.matchPattern}” ',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.inkSoft)),
                TextSpan(
                    text: '→ ${alias.canonicalName}',
                    style: Theme.of(context).textTheme.bodyMedium),
              ]),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                ref.read(merchantAliasProvider.notifier).remove(alias.id!),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
