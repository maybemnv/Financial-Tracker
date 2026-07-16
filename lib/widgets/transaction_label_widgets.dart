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
              children: [
                ..._colors.map((color) {
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
                }),
                Tooltip(
                  message: 'Custom color',
                  child: InkWell(
                    onTap: _pickCustomColor,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.paper,
                        border: Border.all(color: AppTheme.ink, width: 1.5),
                      ),
                      child: const Icon(Icons.colorize_rounded, size: 18),
                    ),
                  ),
                ),
              ],
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

  Future<void> _pickCustomColor() async {
    final initial = TransactionLabel(name: '', color: _color).colorValue;
    var red = (initial.r * 255.0).round().clamp(0, 255);
    var green = (initial.g * 255.0).round().clamp(0, 255);
    var blue = (initial.b * 255.0).round().clamp(0, 255);

    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Pick custom color'),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Color.fromARGB(255, red, green, blue),
                    border: Border.all(color: AppTheme.ink),
                  ),
                ),
                const SizedBox(height: 16),
                _rgbSlider('R', red, 0, (v) => setDialogState(() => red = v)),
                _rgbSlider('G', green, 0, (v) => setDialogState(() => green = v)),
                _rgbSlider('B', blue, 0, (v) => setDialogState(() => blue = v)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                Color.fromARGB(255, red, green, blue),
              ),
              child: const Text('Select'),
            ),
          ],
        ),
      ),
    );

    if (picked != null) {
      setState(() {
        final cr = (picked.r * 255).round();
        final cg = (picked.g * 255).round();
        final cb = (picked.b * 255).round();
        _color = '#${cr.toRadixString(16).padLeft(2, '0')}${cg.toRadixString(16).padLeft(2, '0')}${cb.toRadixString(16).padLeft(2, '0').toUpperCase()}';
      });
    }
  }

  Widget _rgbSlider(String label, int value, int index, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('$value', style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
