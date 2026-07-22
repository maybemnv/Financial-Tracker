import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/account.dart';
import '../../models/transaction.dart';
import '../../models/transaction_label.dart';
import '../../providers/account_provider.dart';
import '../../core/ledger_query.dart';
import '../../providers/aggregate_provider.dart';
import '../../providers/label_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/newsprint_primitives.dart';
import '../../widgets/transaction_label_widgets.dart';
import '../labels/review_queue_screen.dart';

final _currency =
    NumberFormat.currency(symbol: '\u20B9', decimalDigits: 2, locale: 'en_IN');

const _allAccounts = 'all';

class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});

  @override
  ConsumerState<TransactionListScreen> createState() =>
      _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Requests the next page while the user is still a screen away from the
  /// end, so paging is invisible. The notifier suppresses concurrent calls,
  /// so firing on every scroll frame is safe.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      ref.read(ledgerProvider.notifier).loadMore();
    }
  }

  void _updateQuery(LedgerQuery Function(LedgerQuery) change) {
    final notifier = ref.read(ledgerProvider.notifier);
    notifier.setQuery(change(ref.read(ledgerProvider).query));
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider);
    final accountsAsync = ref.watch(accountProvider);
    final labelsAsync = ref.watch(labelProvider);

    return NewsprintPage(
      kicker: 'Ledger',
      title: 'Daily money ledger',
      subtitle: 'Every inflow, outflow, transfer, and investment leg in one ruled stack.',
      child: Column(
        children: [
          accountsAsync.maybeWhen(
            data: (accounts) => _AccountBar(
              accounts: accounts,
              selected: ledger.query.accountId ?? _allAccounts,
              onSelected: (value) => _updateQuery((q) => value == _allAccounts
                  ? q.copyWith(clearAccount: true)
                  : q.copyWith(accountId: value)),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          labelsAsync.maybeWhen(
            // Merged and deleted labels stay readable for historical
            // attribution but are noise as filters; archived ones remain
            // useful for finding older transactions.
            data: (labels) => _LabelBar(
              labels: labels
                  .where((l) => l.isActive || l.isArchived)
                  .toList(growable: false),
              selectedId: ledger.query.labelId,
              onSelected: (id) => _updateQuery((q) => id == null
                  ? q.copyWith(clearLabel: true)
                  : q.copyWith(labelId: id)),
              onCreate: _createLabel,
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const _ReviewBanner(),
          Expanded(child: _LedgerBody(
            ledger: ledger,
            scrollController: _scrollController,
            onLabelTap: (label) =>
                _updateQuery((q) => q.copyWith(labelId: label.id)),
          )),
        ],
      ),
    );
  }

  Future<void> _createLabel() async {
    final created = await showDialog<({String name, String color})>(
      context: context,
      builder: (_) => const CreateTransactionLabelDialog(),
    );
    if (created == null || !mounted) return;
    try {
      await ref.read(labelProvider.notifier).create(
            name: created.name,
            color: created.color,
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create label: $error')),
      );
    }
  }
}

/// Surfaces unattributed spend where it is noticed. Only appears when there is
/// something to fix — expenses carrying several labels with no primary, whose
/// amount currently counts toward no category at all.
class _ReviewBanner extends ConsumerWidget {
  const _ReviewBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Whole-ledger count from the aggregate: the rows needing review are
    // usually old ones, which the first page does not contain.
    final pending = ref.watch(needsPrimaryCountProvider);
    if (pending == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: AppTheme.paperAlt,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ReviewQueueScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.rule_rounded, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$pending expense${pending == 1 ? '' : 's'} '
                    "need${pending == 1 ? 's' : ''} a primary label — "
                    'until then the amount counts under no category.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paged ledger body: first-page load, error, empty, rows, and the
/// next-page footer. A next-page failure keeps the rows already on screen and
/// offers a localized retry instead of blanking the list (TODO 7.2).
class _LedgerBody extends ConsumerWidget {
  const _LedgerBody({
    required this.ledger,
    required this.scrollController,
    required this.onLabelTap,
  });

  final LedgerState ledger;
  final ScrollController scrollController;
  final ValueChanged<TransactionLabel> onLabelTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ledger.isLoadingFirstPage) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ledger.error != null) {
      return Center(
        child: NewsprintNotice(
          icon: Icons.error_outline_rounded,
          title: 'Ledger feed interrupted',
          message: '${ledger.error}',
          color: AppTheme.redAccent,
        ),
      );
    }

    return _LedgerList(
      transactions: ledger.rows,
      scrollController: scrollController,
      onRefresh: () => ref.read(ledgerProvider.notifier).refresh(),
      onLabelTap: onLabelTap,
      footer: _PageFooter(ledger: ledger),
    );
  }
}

class _PageFooter extends ConsumerWidget {
  const _PageFooter({required this.ledger});

  final LedgerState ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ledger.pageError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text('Could not load more.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: () => ref.read(ledgerProvider.notifier).loadMore(),
              child: const Text('RETRY'),
            ),
          ],
        ),
      );
    }
    if (ledger.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (!ledger.hasMore && ledger.rows.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text('End of ledger',
              style: Theme.of(context).textTheme.labelSmall),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

class _AccountBar extends StatelessWidget {
  const _AccountBar({
    required this.accounts,
    required this.selected,
    required this.onSelected,
  });

  final List<Account> accounts;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NewsprintPanel(
        color: AppTheme.paperAlt,
        child: SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _chip('All desks', _allAccounts),
              ...accounts.map((account) => _chip(account.name, account.id!)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    final isSelected = selected == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onSelected(value),
        showCheckmark: false,
        backgroundColor: AppTheme.paper,
        selectedColor: AppTheme.ink,
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.paper : AppTheme.ink,
          fontWeight: FontWeight.w800,
        ),
        side: const BorderSide(color: AppTheme.ink, width: 1.5),
        shape: const RoundedRectangleBorder(),
      ),
    );
  }
}

class _LabelBar extends StatelessWidget {
  const _LabelBar({
    required this.labels,
    required this.selectedId,
    required this.onSelected,
    required this.onCreate,
  });

  final List<TransactionLabel> labels;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NewsprintPanel(
        color: AppTheme.paperAlt,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('LABELS', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('CREATE LABEL'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('All labels'),
                  selected: selectedId == null,
                  onSelected: (_) => onSelected(null),
                  showCheckmark: false,
                ),
                ...labels.map(
                  (label) => TransactionLabelPill(
                    label: label,
                    selected: selectedId == label.id,
                    onTap: () => onSelected(
                      selectedId == label.id ? null : label.id,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LedgerList extends StatelessWidget {
  const _LedgerList({
    required this.transactions,
    required this.onRefresh,
    required this.onLabelTap,
    this.scrollController,
    this.footer,
  });

  final List<Transaction> transactions;
  final Future<void> Function() onRefresh;
  final ValueChanged<TransactionLabel> onLabelTap;
  final ScrollController? scrollController;

  /// Next-page spinner, retry, or end-of-list marker.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long,
        title: 'No transactions match',
        subtitle: 'Clear a filter or add a movement to the ledger.',
      );
    }
    // The server already returns rows in (effective date DESC, id DESC)
    // order; re-sorting here would fight the cursor and could reorder rows
    // across a page boundary.
    final grouped = <DateTime, List<Transaction>>{};
    for (final transaction in transactions) {
      final date = transaction.effectiveDate;
      final key = DateTime(date.year, date.month, date.day);
      grouped.putIfAbsent(key, () => []).add(transaction);
    }
    final items = <Object>[];
    for (final entry in grouped.entries) {
      items.add(entry.key);
      items.addAll(entry.value);
    }
    if (footer != null) items.add(footer!);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: scrollController,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          if (item is DateTime) return _DateHeader(date: item);
          if (item is Widget) return item;
          return _TransactionCard(
            tx: item as Transaction,
            onLabelTap: onLabelTap,
          );
        },
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final current = DateTime(date.year, date.month, date.day);
    final label = current == today
        ? 'Today'
        : current == yesterday
            ? 'Yesterday'
            : DateFormat('EEE, dd MMM yyyy').format(date);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(label.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

class _TransactionCard extends ConsumerWidget {
  const _TransactionCard({required this.tx, required this.onLabelTap});

  final Transaction tx;
  final ValueChanged<TransactionLabel> onLabelTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = tx.isTransfer
        ? AppTheme.accentGold
        : tx.isInvestment
            ? AppTheme.accentPurple
            : tx.isInflow
                ? AppTheme.primaryGreen
                : AppTheme.redAccent;
    final title = tx.merchant ??
        tx.vpa ??
        tx.note ??
        (tx.isTransfer ? 'Transfer' : tx.isInvestment ? 'Investment move' : 'Unknown');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.panelDecoration(color: AppTheme.paper),
      child: InkWell(
        onLongPress: () => _confirmDelete(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MovementIcon(transaction: tx, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(_subtitle(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                    if (tx.labels.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: tx.labels
                            .map((label) => TransactionLabelPill(
                                  label: label,
                                  onTap: () => onLabelTap(label),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!tx.isTransfer && !tx.isInvestment)
                        IconButton(
                          onPressed: () => _edit(context),
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          tooltip: 'Edit transaction',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                        ),
                      Text(
                        '${tx.isInflow ? '+' : '-'}${_currency.format(tx.amount)}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: color,
                                  fontFamilyFallback: AppTheme.monoFallback,
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(DateFormat('HH:mm').format(tx.effectiveDate),
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    if (tx.isTransfer) {
      parts.add(tx.isInflow ? 'Transfer received' : 'Transfer sent');
    } else if (tx.isInvestment) {
      parts.add(tx.isInflow ? 'Investment received' : 'Investment sent');
    } else {
      parts.add(tx.isInflow ? 'Money received' : 'Money paid');
    }
    if (tx.bank != null && tx.bank!.trim().isNotEmpty) parts.add(tx.bank!);
    if (tx.vpa != null && tx.merchant != null) parts.add(tx.vpa!);
    return parts.join(' | ');
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This keeps the record in the audit history.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && tx.id != null) {
      await ref.read(transactionProvider.notifier).delete(tx.id!);
    }
  }

  Future<void> _edit(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(transaction: tx),
      ),
    );
  }
}

class _MovementIcon extends StatelessWidget {
  const _MovementIcon({required this.transaction, required this.color});

  final Transaction transaction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = transaction.isTransfer
        ? Icons.swap_horiz_rounded
        : transaction.isInvestment
            ? Icons.trending_up_rounded
            : transaction.isInflow
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded;
    return Container(
      width: 44,
      height: 44,
      decoration: AppTheme.panelDecoration(color: color.withAlpha(34)),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key, this.transaction});

  final Transaction? transaction;

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  late final TextEditingController _merchantCtrl;
  late final TextEditingController _vpaCtrl;
  late final TextEditingController _bankCtrl;
  final _selectedLabels = <TransactionLabel>[];
  late String _type;
  String? _accountId;
  String? _destAccountId;
  String? _primaryLabelId;
  DateTime? _transactedAt;
  bool _isSaving = false;

  bool get _needsDestination => _type == 'transfer' || _type == 'investment';
  bool get _isEditing => widget.transaction != null;

  /// Only expenses attribute to a primary label (PRD §4).
  bool get _isExpense => _type == 'debit';

  /// An expense that carries labels must name exactly one of them primary,
  /// otherwise its spend cannot be attributed. No labels at all is fine — the
  /// row reports as Unlabeled.
  bool get _needsPrimaryLabel =>
      _isExpense && _selectedLabels.isNotEmpty && _primaryLabelId == null;

  @override
  void initState() {
    super.initState();
    final transaction = widget.transaction;
    _amountCtrl = TextEditingController(
      text: transaction?.amount.toString() ?? '',
    );
    _merchantCtrl = TextEditingController(text: transaction?.merchant ?? '');
    _vpaCtrl = TextEditingController(text: transaction?.vpa ?? '');
    _bankCtrl = TextEditingController(text: transaction?.bank ?? '');
    _type = transaction?.type ?? 'debit';
    _accountId = transaction?.accountId;
    _transactedAt = transaction?.transactedAt;
    _selectedLabels.addAll(transaction?.labels ?? const []);
    _primaryLabelId = transaction?.primaryLabelId;
    _syncPrimaryLabel();
  }

  /// Keeps the primary label consistent with the current selection: drop it if
  /// its label was deselected, and choose it automatically when there is only
  /// one candidate so the common single-label case needs no extra tap.
  void _syncPrimaryLabel() {
    final ids = _selectedLabels
        .map((label) => label.id)
        .whereType<String>()
        .toList(growable: false);
    if (_primaryLabelId != null && !ids.contains(_primaryLabelId)) {
      _primaryLabelId = null;
    }
    if (_primaryLabelId == null && ids.length == 1) {
      _primaryLabelId = ids.first;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    _vpaCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _transactedAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_transactedAt ?? DateTime.now()),
    );
    if (time == null || !mounted) return;
    setState(() {
      _transactedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountProvider).maybeWhen(
          data: (items) => items,
          orElse: () => <Account>[],
        );
    final labelsAsync = ref.watch(labelProvider);
    final now = DateTime.now();
    final dateLabel = _transactedAt == null
        ? 'Now (tap to set)'
        : (_transactedAt!.year == now.year &&
                _transactedAt!.month == now.month &&
                _transactedAt!.day == now.day)
            ? 'Today, ${DateFormat('HH:mm').format(_transactedAt!)}'
            : DateFormat('dd MMM yyyy, HH:mm').format(_transactedAt!);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Transaction' : 'Add Transaction'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              SegmentedButton<String>(
                segments: _isEditing
                    ? const [
                        ButtonSegment(value: 'debit', label: Text('Debit')),
                        ButtonSegment(value: 'credit', label: Text('Credit')),
                      ]
                    : const [
                        ButtonSegment(value: 'debit', label: Text('Debit')),
                        ButtonSegment(value: 'credit', label: Text('Credit')),
                        ButtonSegment(value: 'transfer', label: Text('Transfer')),
                        ButtonSegment(value: 'investment', label: Text('Invest')),
                      ],
                selected: {_type},
                onSelectionChanged: (value) => setState(() => _type = value.first),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const RoundedRectangleBorder(
                    side: BorderSide(color: AppTheme.ink, width: 2)),
                onTap: _pickDateTime,
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Transaction date & time'),
                subtitle: Text(dateLabel),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(labelText: 'Amount (\u20B9)', prefixText: '\u20B9 '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Required';
                  return double.tryParse(value) == null ? 'Invalid number' : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _accountId,
                decoration: InputDecoration(labelText: _needsDestination ? 'From account' : 'Account'),
                items: accounts
                    .map((account) => DropdownMenuItem(
                          value: account.id ?? '',
                          child: Text(account.name),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _accountId = value),
                validator: (value) => value == null || value.isEmpty
                    ? 'Select an account'
                    : null,
              ),
              const SizedBox(height: 12),
              if (_needsDestination) ...[
                DropdownButtonFormField<String>(
                  initialValue: _destAccountId,
                  decoration: const InputDecoration(labelText: 'To account'),
                  items: accounts
                      .map((account) => DropdownMenuItem(
                            value: account.id ?? '',
                            child: Text(account.name),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => _destAccountId = value),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Select destination'
                      : null,
                ),
                const SizedBox(height: 12),
              ] else ...[
                TextFormField(
                  controller: _merchantCtrl,
                  decoration: const InputDecoration(labelText: 'Merchant / sender / receiver'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vpaCtrl,
                  decoration: const InputDecoration(labelText: 'VPA / UPI ID'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bankCtrl,
                  decoration: const InputDecoration(labelText: 'Bank / source account'),
                ),
                const SizedBox(height: 12),
              ],
              labelsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Labels are unavailable right now.'),
                // Only assignable labels: save_transaction_with_labels rejects
                // archived or merged ones, so offering them would be a trap.
                data: (labels) => _LabelSelector(
                  labels:
                      labels.where((l) => l.isAssignable).toList(growable: false),
                  selected: _selectedLabels,
                  primaryLabelId: _primaryLabelId,
                  showPrimaryPicker: _isExpense,
                  onChanged: (selected) => setState(() {
                    _selectedLabels
                      ..clear()
                      ..addAll(selected);
                    _syncPrimaryLabel();
                  }),
                  onPrimaryChanged: (id) =>
                      setState(() => _primaryLabelId = id),
                  onCreate: _createLabel,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isSaving ? null : _submit,
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEditing ? 'Save Changes' : 'Save Transaction'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<TransactionLabel?> _createLabel() async {
    final created = await showDialog<({String name, String color})>(
      context: context,
      builder: (_) => const CreateTransactionLabelDialog(),
    );
    if (created == null || !mounted) return null;
    try {
      return await ref.read(labelProvider.notifier).create(
            name: created.name,
            color: created.color,
          );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create label: $error')),
        );
      }
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_needsDestination && _accountId == _destAccountId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose different source and destination accounts')),
      );
      return;
    }
    if (_needsPrimaryLabel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose which label this expense counts under'),
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final amount = double.parse(_amountCtrl.text);
      final notifier = ref.read(transactionProvider.notifier);
      if (_isEditing) {
        final original = widget.transaction!;
        await notifier.update(
          Transaction(
            id: original.id,
            amount: amount,
            type: _type,
            direction: _type == 'credit' ? 'inflow' : 'outflow',
            accountId: _accountId,
            merchant:
                _merchantCtrl.text.trim().isEmpty ? null : _merchantCtrl.text.trim(),
            vpa: _vpaCtrl.text.trim().isEmpty ? null : _vpaCtrl.text.trim(),
            bank: _bankCtrl.text.trim().isEmpty ? null : _bankCtrl.text.trim(),
            labels: List.unmodifiable(_selectedLabels),
            primaryLabelId: _primaryLabelId,
            rawSms: original.rawSms,
            rawSmsHash: original.rawSmsHash,
            source: original.source,
            note: original.note,
            usdAmount: original.usdAmount,
            linkedInvoiceId: original.linkedInvoiceId,
            transferGroupId: original.transferGroupId,
            transactedAt: _transactedAt,
          ),
        );
      } else if (_type == 'transfer') {
        await notifier.addTransfer(
          fromAccountId: _accountId!,
          toAccountId: _destAccountId!,
          amount: amount,
          transactedAt: _transactedAt,
          labels: List.unmodifiable(_selectedLabels),
        );
      } else if (_type == 'investment') {
        await notifier.addInvestment(
          fromAccountId: _accountId!,
          toAccountId: _destAccountId!,
          amount: amount,
          transactedAt: _transactedAt,
          labels: List.unmodifiable(_selectedLabels),
        );
      } else {
        await notifier.add(Transaction(
          amount: amount,
          type: _type,
          accountId: _accountId,
          merchant: _merchantCtrl.text.trim().isEmpty ? null : _merchantCtrl.text.trim(),
          vpa: _vpaCtrl.text.trim().isEmpty ? null : _vpaCtrl.text.trim(),
          bank: _bankCtrl.text.trim().isEmpty ? null : _bankCtrl.text.trim(),
          labels: List.unmodifiable(_selectedLabels),
          primaryLabelId: _primaryLabelId,
          source: 'manual',
          transactedAt: _transactedAt,
        ));
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _LabelSelector extends StatelessWidget {
  const _LabelSelector({
    required this.labels,
    required this.selected,
    required this.onChanged,
    required this.onCreate,
    required this.primaryLabelId,
    required this.showPrimaryPicker,
    required this.onPrimaryChanged,
  });

  final List<TransactionLabel> labels;
  final List<TransactionLabel> selected;
  final ValueChanged<List<TransactionLabel>> onChanged;
  final Future<TransactionLabel?> Function() onCreate;

  /// The label this expense's full amount attributes to (PRD §4, D3).
  final String? primaryLabelId;
  final bool showPrimaryPicker;
  final ValueChanged<String?> onPrimaryChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Labels', style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                final label = await onCreate();
                if (label != null) onChanged([...selected, label]);
              },
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('CREATE LABEL'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (labels.isEmpty)
          const Text('Create a label to classify this transaction.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: labels.map((label) {
              final isSelected = selected.any((item) => item.id == label.id);
              return TransactionLabelPill(
                label: label,
                selected: isSelected,
                onTap: () => onChanged(
                  isSelected
                      ? selected.where((item) => item.id != label.id).toList()
                      : [...selected, label],
                ),
              );
            }).toList(),
          ),
        if (showPrimaryPicker && selected.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Counts under',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(
            selected.length == 1
                ? 'The full amount attributes to this label.'
                : 'Pick the one label this expense counts under. The others '
                    'stay attached for search and filtering, but the amount is '
                    'never split across them.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final label in selected)
                if (label.id != null)
                  ChoiceChip(
                    label: Text(label.name),
                    selected: label.id == primaryLabelId,
                    onSelected: (_) => onPrimaryChanged(label.id),
                  ),
            ],
          ),
          if (primaryLabelId == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Choose one to save.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.redAccent),
              ),
            ),
        ],
      ],
    );
  }
}
