import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/goal.dart';
import '../../providers/goal_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/newsprint_primitives.dart';

final currencyFormat = NumberFormat.currency(symbol: 'INR ', decimalDigits: 0, locale: 'en_IN');

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(goalProvider);

    return NewsprintPage(
      kicker: 'Targets',
      title: 'Savings board',
      subtitle: 'Emergency cash stays pinned. Everything else competes for allocation below it.',
      actions: [
        FilledButton.icon(
          onPressed: () => _showAddGoalDialog(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('NEW GOAL'),
        ),
      ],
      child: goalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: NewsprintNotice(
            icon: Icons.error_outline_rounded,
            title: 'Goal desk offline',
            message: '$e',
            color: AppTheme.redAccent,
          ),
        ),
        data: (goals) {
          if (goals.isEmpty) {
            return const EmptyState(
              icon: Icons.flag_rounded,
              title: 'No goals yet',
              subtitle: 'Create a fund, device, or buffer target to turn idle cash into a visible plan.',
            );
          }

          final sorted = _sorted(goals);
          final totalTarget = sorted.fold<double>(0, (sum, goal) => sum + goal.targetAmount);
          final totalSaved = sorted.fold<double>(0, (sum, goal) => sum + goal.allocatedAmount);

          return RefreshIndicator(
            onRefresh: () => ref.read(goalProvider.notifier).load(),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    NewsprintMetricStrip(label: 'Goals', value: '${sorted.length}'),
                    NewsprintMetricStrip(label: 'Saved', value: currencyFormat.format(totalSaved)),
                    NewsprintMetricStrip(label: 'Target', value: currencyFormat.format(totalTarget)),
                  ],
                ),
                const SizedBox(height: 12),
                ...sorted.map((goal) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _GoalCard(goal: goal),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddGoalDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => const _AddGoalDialog(),
    );
  }

  List<Goal> _sorted(List<Goal> goals) {
    final copy = [...goals];
    copy.sort((a, b) {
      if (a.isEmergencyFund && !b.isEmergencyFund) return -1;
      if (!a.isEmergencyFund && b.isEmergencyFund) return 1;
      return 0;
    });
    return copy;
  }
}

class _AddGoalDialog extends ConsumerStatefulWidget {
  const _AddGoalDialog();

  @override
  ConsumerState<_AddGoalDialog> createState() => _AddGoalDialogState();
}

class _AddGoalDialogState extends ConsumerState<_AddGoalDialog> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _type = 'custom';
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Goal'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Goal Name *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            decoration: const InputDecoration(labelText: 'Target Amount (INR) *'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'custom', label: Text('Custom')),
              ButtonSegment(value: 'emergency_fund', label: Text('Emergency Fund')),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('CREATE'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.isEmpty || _amountCtrl.text.isEmpty) return;
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid target amount')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(goalProvider.notifier).add(Goal(
            name: _nameCtrl.text,
            targetAmount: amount,
            type: _type,
          ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create goal: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pct = goal.fundedPercent.clamp(0, 100).toDouble();
    final remaining = (goal.targetAmount - goal.allocatedAmount).clamp(0, double.infinity);

    return NewsprintPanel(
      color: goal.isEmergencyFund ? AppTheme.paper : AppTheme.paperAlt,
      accentTop: goal.isEmergencyFund,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (goal.isEmergencyFund)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: NewsprintTag(label: 'Emergency fund'),
                      ),
                    Text(goal.name, style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
              ),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                      color: goal.isEmergencyFund ? AppTheme.redAccent : AppTheme.ink,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRect(
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 14,
              backgroundColor: AppTheme.paperMuted,
              valueColor: AlwaysStoppedAnimation<Color>(
                goal.isEmergencyFund ? AppTheme.redAccent : AppTheme.ink,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              NewsprintMetricStrip(label: 'Saved', value: currencyFormat.format(goal.allocatedAmount)),
              NewsprintMetricStrip(label: 'Target', value: currencyFormat.format(goal.targetAmount)),
              NewsprintMetricStrip(label: 'Remaining', value: currencyFormat.format(remaining)),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () => _showAllocateDialog(context),
            child: const Text('ALLOCATE FUNDS'),
          ),
        ],
      ),
    );
  }

  void _showAllocateDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _AllocateDialog(goal: goal),
    );
  }
}

class _AllocateDialog extends ConsumerStatefulWidget {
  const _AllocateDialog({required this.goal});

  final Goal goal;

  @override
  ConsumerState<_AllocateDialog> createState() => _AllocateDialogState();
}

class _AllocateDialogState extends ConsumerState<_AllocateDialog> {
  final _ctrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Allocate Funds'),
      content: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(labelText: 'Amount (INR) *'),
        keyboardType: TextInputType.number,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('ALLOCATE'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_ctrl.text.isEmpty) return;
    final amount = double.tryParse(_ctrl.text);
    if (amount == null || amount <= 0) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(goalProvider.notifier).allocate(widget.goal.id!, amount);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Allocation failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
