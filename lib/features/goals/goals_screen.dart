import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/goal_rules.dart';
import '../../core/theme.dart';
import '../../models/goal.dart';
import '../../models/goal_contribution.dart';
import '../../providers/goal_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/newsprint_primitives.dart';

final currencyFormat =
    NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
final _dayFormat = DateFormat('d MMM yyyy');
final _monthFormat = DateFormat('MMM yyyy');

/// Shown on every dialog that moves earmarked money (TODO 6.3).
const _earmarkNote =
    'Earmarks existing money; no account balance changes.';

/// Dialogs are built for a 360-pixel viewport.
const double _dialogWidth = 360;

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(goalProvider);

    return NewsprintPage(
      kicker: 'Targets',
      title: 'Savings board',
      subtitle:
          'Emergency cash stays pinned. Everything else competes for allocation below it.',
      actions: [
        FilledButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const _AddGoalDialog(),
          ),
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
              subtitle:
                  'Create a fund, device, or buffer target to turn idle cash into a visible plan.',
            );
          }

          final sorted = GoalRules.sorted(goals);
          final live = sorted.where((g) => !g.isArchived).toList();
          final totalTarget =
              live.fold<double>(0, (sum, goal) => sum + goal.targetAmount);
          final totalSaved =
              live.fold<double>(0, (sum, goal) => sum + goal.allocatedAmount);

          return RefreshIndicator(
            onRefresh: () => ref.read(goalProvider.notifier).load(),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    NewsprintMetricStrip(
                        label: 'Goals', value: '${live.length}'),
                    NewsprintMetricStrip(
                        label: 'Earmarked',
                        value: currencyFormat.format(totalSaved)),
                    NewsprintMetricStrip(
                        label: 'Target',
                        value: currencyFormat.format(totalTarget)),
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
}

// --- List card ---------------------------------------------------------------

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final pct = goal.fundedPercent.clamp(0, 100).toDouble();
    final dimmed = goal.isArchived || goal.status == 'paused';

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
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (goal.isEmergencyFund)
                          const NewsprintTag(label: 'Emergency fund'),
                        if (goal.status != 'active')
                          _StatusTag(status: goal.status),
                      ],
                    ),
                    if (goal.isEmergencyFund || goal.status != 'active')
                      const SizedBox(height: 8),
                    Text(
                      goal.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: dimmed ? AppTheme.inkSoft : null,
                          ),
                    ),
                    if (goal.targetDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'By ${_dayFormat.format(goal.targetDate!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                      color: goal.isEmergencyFund
                          ? AppTheme.redAccent
                          : AppTheme.ink,
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
              NewsprintMetricStrip(
                  label: 'Saved',
                  value: currencyFormat.format(goal.allocatedAmount)),
              NewsprintMetricStrip(
                  label: 'Target',
                  value: currencyFormat.format(goal.targetAmount)),
              NewsprintMetricStrip(
                  label: 'Remaining',
                  value: currencyFormat.format(goal.remaining)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: goal.isArchived
                      ? null
                      : () => showDialog<void>(
                            context: context,
                            builder: (_) => _ContributeDialog(goal: goal),
                          ),
                  child: const Text('ADD FUNDS'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => _GoalDetailDialog(goalId: goal.id!),
                  ),
                  child: const Text('DETAILS'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'completed' => AppTheme.primaryGreen,
      'paused' => AppTheme.accentGold,
      'archived' => AppTheme.inkSoft,
      _ => AppTheme.ink,
    };
    return NewsprintTag(
      label: status.toUpperCase(),
      backgroundColor: color,
      textColor: AppTheme.paper,
    );
  }
}

// --- Detail view -------------------------------------------------------------

class _GoalDetailDialog extends ConsumerWidget {
  const _GoalDetailDialog({required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalProvider).valueOrNull ?? const <Goal>[];
    final goal = goals.where((g) => g.id == goalId).firstOrNull;
    if (goal == null) {
      // Deleted while the sheet was open.
      return const _DialogFrame(
        title: 'Goal',
        child: Text('This goal is no longer available.'),
      );
    }

    final historyAsync = ref.watch(goalContributionsProvider(goalId));

    return _DialogFrame(
      title: goal.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (goal.isEmergencyFund)
                const NewsprintTag(label: 'Emergency fund'),
              _StatusTag(status: goal.status),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              NewsprintMetricStrip(
                  label: 'Saved',
                  value: currencyFormat.format(goal.allocatedAmount)),
              NewsprintMetricStrip(
                  label: 'Target',
                  value: currencyFormat.format(goal.targetAmount)),
              NewsprintMetricStrip(
                  label: 'Remaining',
                  value: currencyFormat.format(goal.remaining)),
              NewsprintMetricStrip(
                  label: 'Funded',
                  value: '${goal.fundedPercent.toStringAsFixed(0)}%'),
            ],
          ),
          if (goal.targetDate != null) ...[
            const SizedBox(height: 10),
            Text('Target date: ${_dayFormat.format(goal.targetDate!)}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          const NewsprintSectionTitle(label: 'Allocation'),
          const SizedBox(height: 8),
          historyAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('History unavailable: ${_errorText(e)}',
                style: Theme.of(context).textTheme.bodySmall),
            data: (history) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LatestAllocation(history: history),
                const SizedBox(height: 8),
                _EstimateLine(goal: goal, history: history),
                const SizedBox(height: 14),
                _GoalActions(goal: goal, history: history),
                const SizedBox(height: 16),
                const NewsprintSectionTitle(label: 'History'),
                const SizedBox(height: 6),
                if (history.isEmpty)
                  Text('No allocations recorded yet.',
                      style: Theme.of(context).textTheme.bodySmall)
                else
                  ...history.map((c) => _HistoryRow(contribution: c)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestAllocation extends StatelessWidget {
  const _LatestAllocation({required this.history});

  final List<GoalContribution> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Text('Nothing earmarked yet.',
          style: Theme.of(context).textTheme.bodySmall);
    }
    final latest = history.first;
    final sign = latest.isCorrection ? '−' : '+';
    return Text(
      'Latest: $sign${currencyFormat.format(latest.amount.abs())} '
      'on ${_dayFormat.format(latest.createdAt)}',
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

class _EstimateLine extends StatelessWidget {
  const _EstimateLine({required this.goal, required this.history});

  final Goal goal;
  final List<GoalContribution> history;

  @override
  Widget build(BuildContext context) {
    final estimate =
        GoalRules.estimateCompletion(goal: goal, contributions: history);
    final text = switch (estimate.status) {
      GoalEstimateStatus.estimated =>
        'Estimated completion: ${_monthFormat.format(estimate.projectedMonth!)} '
            '(${currencyFormat.format(estimate.monthlyPace)}/month)',
      GoalEstimateStatus.alreadyFunded => 'Target reached.',
      GoalEstimateStatus.notEnoughHistory =>
        'Estimated completion: not enough history.',
      GoalEstimateStatus.noForwardProgress =>
        'Estimated completion: no forward progress yet.',
      GoalEstimateStatus.beyondHorizon =>
        'Estimated completion: further out than this pace can meaningfully project.',
    };
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.contribution});

  final GoalContribution contribution;

  @override
  Widget build(BuildContext context) {
    final sign = contribution.isCorrection ? '−' : '+';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_dayFormat.format(contribution.createdAt),
                    style: Theme.of(context).textTheme.bodyMedium),
                if (contribution.note != null && contribution.note!.isNotEmpty)
                  Text(contribution.note!,
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            '$sign${currencyFormat.format(contribution.amount.abs())}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: contribution.isCorrection
                      ? AppTheme.redAccent
                      : AppTheme.primaryGreen,
                ),
          ),
        ],
      ),
    );
  }
}

// --- Actions -----------------------------------------------------------------

class _GoalActions extends ConsumerStatefulWidget {
  const _GoalActions({required this.goal, required this.history});

  final Goal goal;
  final List<GoalContribution> history;

  @override
  ConsumerState<_GoalActions> createState() => _GoalActionsState();
}

class _GoalActionsState extends ConsumerState<_GoalActions> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final transitions = GoalRules.allowedTransitions(goal.status);
    final canDelete = GoalRules.canDelete(widget.history.length);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!goal.isArchived)
          OutlinedButton(
            onPressed: _busy ? null : () => _open(_ContributeDialog(goal: goal)),
            child: const Text('ADD FUNDS'),
          ),
        if (!goal.isArchived && goal.allocatedAmount > 0)
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _open(_ContributeDialog(goal: goal, correcting: true)),
            child: const Text('CORRECT'),
          ),
        if (!goal.isArchived && goal.allocatedAmount > 0)
          OutlinedButton(
            onPressed: _busy ? null : () => _open(_ReallocateDialog(goal: goal)),
            child: const Text('REALLOCATE'),
          ),
        if (!goal.isArchived)
          OutlinedButton(
            onPressed: _busy ? null : () => _open(_EditGoalDialog(goal: goal)),
            child: const Text('EDIT'),
          ),
        for (final status in transitions)
          OutlinedButton(
            onPressed: _busy ? null : () => _setStatus(status),
            child: Text(_transitionLabel(goal.status, status)),
          ),
        if (canDelete)
          TextButton(
            onPressed: _busy ? null : _delete,
            child: const Text('DELETE'),
          ),
      ],
    );
  }

  String _transitionLabel(String from, String to) {
    if (to == 'active') return from == 'archived' ? 'RESTORE' : 'RESUME';
    if (to == 'paused') return 'PAUSE';
    return 'ARCHIVE';
  }

  void _open(Widget dialog) {
    showDialog<void>(context: context, builder: (_) => dialog);
  }

  Future<void> _setStatus(String status) async {
    if (status == 'archived') {
      final ok = await _confirm(
        context,
        title: 'Archive goal?',
        message:
            'The goal and its allocation history stay on record; it drops to '
            'the bottom of the board and stops accepting funds.',
        confirmLabel: 'ARCHIVE',
      );
      if (!ok) return;
    }
    await _run(() =>
        ref.read(goalProvider.notifier).setStatus(widget.goal.id!, status));
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      context,
      title: 'Delete goal?',
      message:
          'This goal has no allocation history, so it can be removed. Goals '
          'with history must be archived instead.',
      confirmLabel: 'DELETE',
    );
    if (!ok) return;
    final deleted =
        await _run(() => ref.read(goalProvider.notifier).delete(widget.goal.id!));
    if (deleted && mounted) Navigator.of(context).pop();
  }

  Future<bool> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      return true;
    } catch (e) {
      if (mounted) _showError(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// --- Contribute / correct ----------------------------------------------------

class _ContributeDialog extends ConsumerStatefulWidget {
  const _ContributeDialog({required this.goal, this.correcting = false});

  final Goal goal;

  /// Records a negative row (a correction or a removal) instead of a deposit.
  final bool correcting;

  @override
  ConsumerState<_ContributeDialog> createState() => _ContributeDialogState();
}

class _ContributeDialogState extends ConsumerState<_ContributeDialog> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final correcting = widget.correcting;
    return _DialogFrame(
      title: correcting ? 'Correct allocation' : 'Add funds',
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL')),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(correcting ? 'RECORD' : 'ADD'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.goal.name,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            correcting
                ? 'Removes earmarked money from this goal. Recorded as a new '
                    'negative entry — earlier entries are never edited.'
                : _earmarkNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: correcting
                  ? 'Amount to remove (₹) *'
                  : 'Amount (₹) *',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final magnitude = double.tryParse(_amountCtrl.text.trim());
    if (magnitude == null || magnitude <= 0) {
      _showMessage(context, 'Enter an amount greater than zero.');
      return;
    }
    final amount = widget.correcting ? -magnitude : magnitude;

    if (widget.correcting && widget.goal.allocatedAmount - magnitude < 0) {
      _showMessage(
          context, 'That is more than the goal currently has earmarked.');
      return;
    }

    var allowOverfunding = false;
    if (GoalRules.wouldOverfund(widget.goal, amount)) {
      final over =
          widget.goal.allocatedAmount + amount - widget.goal.targetAmount;
      allowOverfunding = await _confirm(
        context,
        title: 'Overfund this goal?',
        message: 'This puts ${currencyFormat.format(over)} above the target. '
            '$_earmarkNote',
        confirmLabel: 'OVERFUND',
      );
      if (!allowOverfunding) return;
    }

    setState(() => _isSaving = true);
    try {
      final note = _noteCtrl.text.trim();
      await ref.read(goalProvider.notifier).contribute(
            widget.goal.id!,
            amount,
            note: note.isEmpty ? null : note,
            allowOverfunding: allowOverfunding,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// --- Reallocate --------------------------------------------------------------

class _ReallocateDialog extends ConsumerStatefulWidget {
  const _ReallocateDialog({required this.goal});

  final Goal goal;

  @override
  ConsumerState<_ReallocateDialog> createState() => _ReallocateDialogState();
}

class _ReallocateDialogState extends ConsumerState<_ReallocateDialog> {
  final _amountCtrl = TextEditingController();
  String? _targetId;
  bool _isSaving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final goals = ref.watch(goalProvider).valueOrNull ?? const <Goal>[];
    final targets = GoalRules.sorted(goals)
        .where((g) => g.id != widget.goal.id && !g.isArchived)
        .toList();

    return _DialogFrame(
      title: 'Reallocate',
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL')),
        FilledButton(
          onPressed: _isSaving || targets.isEmpty ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('MOVE'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('From ${widget.goal.name}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Moves an earmark between goals. $_earmarkNote',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (targets.isEmpty)
            Text('Create another goal first.',
                style: Theme.of(context).textTheme.bodySmall)
          else
            DropdownButtonFormField<String>(
              initialValue: _targetId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'To goal *'),
              items: targets
                  .map((g) => DropdownMenuItem(
                        value: g.id,
                        child: Text(g.name, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _targetId = v),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            decoration: const InputDecoration(labelText: 'Amount (₹) *'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          Text(
            'Available here: ${currencyFormat.format(widget.goal.allocatedAmount)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final targetId = _targetId;
    if (targetId == null) {
      _showMessage(context, 'Choose a goal to move funds into.');
      return;
    }
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      _showMessage(context, 'Enter an amount greater than zero.');
      return;
    }
    if (amount > widget.goal.allocatedAmount) {
      _showMessage(context, 'This goal does not have that much earmarked.');
      return;
    }

    final goals = ref.read(goalProvider).valueOrNull ?? const <Goal>[];
    final target = goals.where((g) => g.id == targetId).firstOrNull;
    var allowOverfunding = false;
    if (target != null && GoalRules.wouldOverfund(target, amount)) {
      final over = target.allocatedAmount + amount - target.targetAmount;
      allowOverfunding = await _confirm(
        context,
        title: 'Overfund ${target.name}?',
        message: 'This puts ${currencyFormat.format(over)} above that target.',
        confirmLabel: 'OVERFUND',
      );
      if (!allowOverfunding) return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(goalProvider.notifier).reallocate(
            fromGoalId: widget.goal.id!,
            toGoalId: targetId,
            amount: amount,
            allowOverfunding: allowOverfunding,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// --- Edit --------------------------------------------------------------------

class _EditGoalDialog extends ConsumerStatefulWidget {
  const _EditGoalDialog({required this.goal});

  final Goal goal;

  @override
  ConsumerState<_EditGoalDialog> createState() => _EditGoalDialogState();
}

class _EditGoalDialogState extends ConsumerState<_EditGoalDialog> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.goal.name);
  late final TextEditingController _amountCtrl = TextEditingController(
      text: widget.goal.targetAmount.toStringAsFixed(0));
  late String _type = widget.goal.type;
  late DateTime? _targetDate = widget.goal.targetDate;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: 'Edit goal',
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL')),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('SAVE'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Goal Name *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            decoration:
                const InputDecoration(labelText: 'Target Amount (₹) *'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _targetDate == null
                      ? 'No target date'
                      : 'By ${_dayFormat.format(_targetDate!)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TextButton(onPressed: _pickDate, child: const Text('PICK DATE')),
              if (_targetDate != null)
                TextButton(
                  onPressed: () => setState(() => _targetDate = null),
                  child: const Text('CLEAR'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'custom', label: Text('Custom')),
              ButtonSegment(
                  value: 'emergency_fund', label: Text('Emergency Fund')),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 30),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showMessage(context, 'Goal name is required.');
      return;
    }
    final target = double.tryParse(_amountCtrl.text.trim());
    if (target == null || target <= 0) {
      _showMessage(context, 'Enter a target greater than zero.');
      return;
    }

    var allowBelow = false;
    if (GoalRules.targetBelowAllocated(widget.goal, target)) {
      allowBelow = await _confirm(
        context,
        title: 'Target below earmarked amount?',
        message:
            '${currencyFormat.format(widget.goal.allocatedAmount)} is already '
            'earmarked here, so the goal becomes overfunded. No money moves.',
        confirmLabel: 'SAVE ANYWAY',
      );
      if (!allowBelow) return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(goalProvider.notifier).updateGoal(
            goalId: widget.goal.id!,
            name: name,
            targetAmount: target,
            targetDate: _targetDate,
            type: _type,
            allowTargetBelowAllocated: allowBelow,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// --- Create ------------------------------------------------------------------

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
    return _DialogFrame(
      title: 'New Goal',
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL')),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('CREATE'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Goal Name *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            decoration:
                const InputDecoration(labelText: 'Target Amount (₹) *'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'custom', label: Text('Custom')),
              ButtonSegment(
                  value: 'emergency_fund', label: Text('Emergency Fund')),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _amountCtrl.text.trim().isEmpty) return;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      _showMessage(context, 'Invalid target amount');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(goalProvider.notifier).add(Goal(
            name: _nameCtrl.text.trim(),
            targetAmount: amount,
            type: _type,
          ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// --- Shared dialog chrome ----------------------------------------------------

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    required this.child,
    this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _dialogWidth),
        child: SingleChildScrollView(child: child),
      ),
      actions: actions ??
          [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE')),
          ],
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _dialogWidth),
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

String _errorText(Object error) =>
    error is PostgrestException ? error.message : '$error';

void _showError(BuildContext context, Object error) =>
    _showMessage(context, _errorText(error));

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}
