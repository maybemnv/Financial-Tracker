import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/goal.dart';
import '../../providers/goal_provider.dart';
import '../../widgets/empty_state.dart';

final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2, locale: 'en_IN');

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(goalProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Goals')),
      body: goalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.redAccent),
              const SizedBox(height: 16),
              Text('$e', style: const TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(goalProvider.notifier).load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (goals) {
          if (goals.isEmpty) {
            return const EmptyState(
              icon: Icons.flag,
              title: 'No goals yet',
              subtitle: 'Set a savings goal to track your progress',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(goalProvider.notifier).load(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: goals.length,
              itemBuilder: (context, index) => _GoalCard(goal: goals[index]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddGoalDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddGoalDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _AddGoalDialog(),
    );
  }
}

class _AddGoalDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AddGoalDialog> createState() => _AddGoalDialogState();
}

class _AddGoalDialogState extends ConsumerState<_AddGoalDialog> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
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
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Goal Name *')),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            decoration: const InputDecoration(labelText: 'Target Amount (₹) *'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create'),
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
  final Goal goal;
  const _GoalCard({required this.goal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pct = goal.fundedPercent;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(goal.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 10,
                backgroundColor: AppTheme.darkBg,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${currencyFormat.format(goal.allocatedAmount)} saved', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                Text('Target: ${currencyFormat.format(goal.targetAmount)}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _showAllocateDialog(context, ref),
                child: const Text('Allocate Funds'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAllocateDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _AllocateDialog(goal: goal),
    );
  }
}

class _AllocateDialog extends ConsumerStatefulWidget {
  final Goal goal;
  const _AllocateDialog({required this.goal});

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
        decoration: const InputDecoration(labelText: 'Amount (₹) *'),
        keyboardType: TextInputType.number,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Allocate'),
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
