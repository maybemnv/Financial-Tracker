import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/transaction_label.dart';

class TransactionLabelPill extends StatelessWidget {
  const TransactionLabelPill({
    super.key,
    required this.label,
    this.onTap,
    this.selected = false,
    this.onRemove,
  });

  final TransactionLabel label;
  final VoidCallback? onTap;
  final bool selected;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final background = label.colorValue;
    final foreground = background.computeLuminance() > 0.45
        ? AppTheme.ink
        : AppTheme.paper;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.fromLTRB(9, 6, onRemove == null ? 9 : 4, 6),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(
              color: AppTheme.ink,
              width: selected ? 3 : 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.name.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground,
                      letterSpacing: 0.9,
                    ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: onRemove,
                  child: Icon(Icons.close_rounded, size: 14, color: foreground),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CreateTransactionLabelDialog extends StatefulWidget {
  const CreateTransactionLabelDialog({super.key});

  @override
  State<CreateTransactionLabelDialog> createState() =>
      _CreateTransactionLabelDialogState();
}

class _CreateTransactionLabelDialogState
    extends State<CreateTransactionLabelDialog> {
  static const _colors = [
    '#B60205',
    '#D93F0B',
    '#FBCA04',
    '#0E8A16',
    '#006B75',
    '#1D76DB',
    '#5319E7',
    '#C5DEF5',
    '#F9D0C4',
    '#BFDADC',
  ];

  final _nameController = TextEditingController();
  String _color = _colors.first;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create label'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Label name'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Text('Color', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _colors.map((color) {
                final selected = color == _color;
                return Tooltip(
                  message: color,
                  child: InkWell(
                    onTap: () => setState(() => _color = color),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: TransactionLabel(name: '', color: color).colorValue,
                        border: Border.all(
                          color: AppTheme.ink,
                          width: selected ? 3 : 1.5,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name: name, color: _color));
  }
}
