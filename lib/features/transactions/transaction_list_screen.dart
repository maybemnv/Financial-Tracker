import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../models/account.dart';
import '../../models/transaction.dart';
import '../../providers/account_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/empty_state.dart';

final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2, locale: 'en_IN');

const _allAccounts = 'all';

// ---------------------------------------------------------------------------
// TransactionListScreen — Paytm-style: grouped by date, time on each row.
// ---------------------------------------------------------------------------

class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});

  @override
  ConsumerState<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  String _accountFilter = _allAccounts;

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionProvider);
    final accountsAsync = ref.watch(accountProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: Column(
        children: [
          // Account filter chips
          accountsAsync.maybeWhen(
            data: (accounts) {
              if (accounts.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    _filterChip('All', _allAccounts),
                    ...accounts.map((a) => _filterChip(a.name, a.id!)),
                  ],
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: transactionsAsync.when(
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
                      onPressed: () => ref.read(transactionProvider.notifier).load(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (transactions) {
                final filtered = _accountFilter == _allAccounts
                    ? transactions
                    : transactions.where((t) => t.accountId == _accountFilter).toList();

                if (filtered.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long,
                    title: 'No transactions yet',
                    subtitle: 'Tap + to add your first transaction',
                  );
                }

                // Sort by effectiveDate descending (user-set date, else server timestamp)
                final sorted = [...filtered]
                  ..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));

                // Group by calendar date
                final grouped = <DateTime, List<Transaction>>{};
                for (final tx in sorted) {
                  final d = tx.effectiveDate;
                  final key = DateTime(d.year, d.month, d.day);
                  grouped.putIfAbsent(key, () => []).add(tx);
                }

                // Flatten: [DateTime header, Transaction, Transaction, ...]
                final items = <Object>[];
                final sortedKeys = grouped.keys.toList()
                  ..sort((a, b) => b.compareTo(a));
                for (final key in sortedKeys) {
                  items.add(key);
                  items.addAll(grouped[key]!);
                }

                return RefreshIndicator(
                  onRefresh: () => ref.read(transactionProvider.notifier).load(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      if (item is DateTime) {
                        return _DateHeader(date: item);
                      }
                      return _TransactionCard(tx: item as Transaction);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _accountFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _accountFilter = value),
        selectedColor: AppTheme.primaryGreen.withAlpha(40),
        checkmarkColor: AppTheme.primaryGreen,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date section header — "Today", "Yesterday", or "Fri, 27 Jun"
// ---------------------------------------------------------------------------

class _DateHeader extends StatelessWidget {
  final DateTime date;
  const _DateHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);

    final String label;
    if (d == today) {
      label = 'Today';
    } else if (d == yesterday) {
      label = 'Yesterday';
    } else {
      label = DateFormat('EEE, dd MMM yyyy').format(date);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transaction card — Paytm-style: icon | merchant + meta | amount + time
// ---------------------------------------------------------------------------

class _TransactionCard extends ConsumerWidget {
  final Transaction tx;
  const _TransactionCard({required this.tx});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCredit = tx.isCredit;
    final isTransfer = tx.isTransfer;
    final isInvestment = tx.isInvestment;

    final color = isCredit
        ? AppTheme.primaryGreen
        : isTransfer
            ? AppTheme.accentGold
            : isInvestment
                ? AppTheme.accentPurple
                : AppTheme.redAccent;

    final sign = isCredit ? '+' : '-';

        final timeStr = DateFormat('HH:mm').format(tx.effectiveDate);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: color.withAlpha(30),
          child: Icon(
            isCredit
                ? Icons.arrow_downward_rounded
                : isTransfer
                    ? Icons.swap_horiz_rounded
                    : isInvestment
                        ? Icons.trending_up_rounded
                        : Icons.arrow_upward_rounded,
            color: color,
            size: 20,
          ),
        ),
        title: Text(
          tx.merchant ?? tx.vpa ?? tx.note ?? 'Unknown',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              _subtitle(),
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (tx.tags.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: tx.tags
                    .map((tag) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen.withAlpha(25),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: AppTheme.primaryGreen.withAlpha(60)),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.primaryGreen,
                                fontWeight: FontWeight.w500),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$sign${_currency.format(tx.amount)}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              timeStr,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        onLongPress: () => _confirmDelete(context, ref),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    if (tx.type == 'transfer') {
      parts.add('Transfer');
    } else if (tx.type == 'investment') {
      parts.add('Investment');
    } else if (tx.category != null) {
      parts.add(tx.category!);
    }
    if (tx.bank != null) { parts.add(tx.bank!); }
    if (tx.vpa != null && tx.merchant != null) { parts.add(tx.vpa!); }
    return parts.join(' • ');
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text(
            'This soft-deletes the transaction. It stays in your audit history but won\'t appear in the app.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && tx.id != null) {
      await ref.read(transactionProvider.notifier).delete(tx.id!);
    }
  }
}

// ---------------------------------------------------------------------------
// AddTransactionScreen — with date + time picker (defaults to now)
// ---------------------------------------------------------------------------

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _merchantCtrl = TextEditingController();
  final _vpaCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _tagFocus = FocusNode();
  String _type = 'debit';
  String _category = 'Other';
  String? _accountId;
  String? _destAccountId;
  DateTime? _transactedAt; // null = "Now" (server default); only set when user explicitly picks
  final List<String> _tags = [];
  bool _isSaving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    _vpaCtrl.dispose();
    _tagCtrl.dispose();
    _tagFocus.dispose();
    super.dispose();
  }

  void _addTag() {
    final raw = _tagCtrl.text.trim();
    if (raw.isEmpty) return;
    // Normalise: lowercase, no duplicate
    final tag = raw.toLowerCase();
    if (!_tags.contains(tag)) {
      setState(() => _tags.add(tag));
    }
    _tagCtrl.clear();
    _tagFocus.requestFocus();
  }

  void _removeTag(String tag) => setState(() => _tags.remove(tag));

  bool get _needsDestination => _type == 'transfer' || _type == 'investment';

  Future<void> _pickDateTime() async {
    // Step 1: pick date
    final date = await showDatePicker(
      context: context,
      initialDate: _transactedAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTheme.primaryGreen),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    // Step 2: pick time
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_transactedAt ?? DateTime.now()),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTheme.primaryGreen),
        ),
        child: child!,
      ),
    );
    if (time == null) return;

    setState(() {
      _transactedAt = DateTime(
        date.year, date.month, date.day,
        time.hour, time.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountProvider);
    final accounts = accountsAsync.maybeWhen(data: (a) => a, orElse: () => <Account>[]);

    final now = DateTime.now();
    final dateLabel = _transactedAt == null
        ? 'Now (tap to set)'
        : (_transactedAt!.year == now.year &&
                _transactedAt!.month == now.month &&
                _transactedAt!.day == now.day)
            ? 'Today, ${DateFormat('HH:mm').format(_transactedAt!)}'
            : DateFormat('dd MMM yyyy, HH:mm').format(_transactedAt!);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Transaction')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Transaction type toggle
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'debit', label: Text('Debit')),
                  ButtonSegment(value: 'credit', label: Text('Credit')),
                  ButtonSegment(value: 'transfer', label: Text('Transfer')),
                  ButtonSegment(value: 'investment', label: Text('Invest')),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
              const SizedBox(height: 16),

              // Date & time picker — Paytm-style row
              InkWell(
                onTap: _pickDateTime,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.textSecondary.withAlpha(80)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 18, color: AppTheme.textSecondary),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Transaction date & time',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textSecondary)),
                          const SizedBox(height: 2),
                          Text(dateLabel,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right,
                          color: AppTheme.textSecondary, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Amount
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                    labelText: 'Amount (₹)', prefixText: '₹ '),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (double.tryParse(v) == null) return 'Invalid number';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Source account
              DropdownButtonFormField<String>(
                initialValue: _accountId,
                decoration: InputDecoration(
                  labelText: _type == 'transfer' || _type == 'investment'
                      ? 'From account'
                      : 'Account',
                ),
                items: accounts
                    .map((a) =>
                        DropdownMenuItem(value: a.id ?? '', child: Text(a.name)))
                    .toList(),
                onChanged: (v) => setState(() => _accountId = v),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Select an account' : null,
              ),
              const SizedBox(height: 12),

              // Destination account (transfers / investments only)
              if (_needsDestination) ...[
                DropdownButtonFormField<String>(
                  initialValue: _destAccountId,
                  decoration: InputDecoration(
                    labelText: _type == 'transfer'
                        ? 'To account'
                        : 'Destination account',
                  ),
                  items: accounts
                      .map((a) => DropdownMenuItem(
                          value: a.id ?? '', child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _destAccountId = v),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Select destination' : null,
                ),
                const SizedBox(height: 12),
              ],

              // Merchant / VPA / Category (debit + credit only)
              if (!_needsDestination) ...[
                TextFormField(
                  controller: _merchantCtrl,
                  decoration: const InputDecoration(labelText: 'Merchant / Description'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vpaCtrl,
                  decoration: const InputDecoration(labelText: 'VPA / UPI ID'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: AppConstants.categories
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _category = v!),
                ),
              ],
              const SizedBox(height: 16),

              // Custom tags
              _TagInput(
                tags: _tags,
                controller: _tagCtrl,
                focusNode: _tagFocus,
                onAdd: _addTag,
                onRemove: _removeTag,
              ),
              const SizedBox(height: 24),

              FilledButton(
                onPressed: _isSaving ? null : _submit,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Transaction'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final amount = double.parse(_amountCtrl.text);
      if (_type == 'transfer') {
        await ref.read(transactionProvider.notifier).addTransfer(
              fromAccountId: _accountId!,
              toAccountId: _destAccountId!,
              amount: amount,
              transactedAt: _transactedAt,
            );
      } else {
        final tx = Transaction(
          amount: amount,
          type: _type,
          accountId: _accountId,
          merchant:
              _merchantCtrl.text.isNotEmpty ? _merchantCtrl.text : null,
          vpa: _vpaCtrl.text.isNotEmpty ? _vpaCtrl.text : null,
          category: _needsDestination ? null : _category,
          tags: List.unmodifiable(_tags),
          source: 'manual',
          transactedAt: _transactedAt,
        );
        await ref.read(transactionProvider.notifier).add(tx);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// _TagInput — free-form tag builder with chip display
// Type a tag → press Enter or the + button to add.
// Tap × on a chip to remove. Tags are normalised to lowercase.
// ---------------------------------------------------------------------------

class _TagInput extends StatelessWidget {
  final List<String> tags;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onAdd;
  final void Function(String) onRemove;

  const _TagInput({
    required this.tags,
    required this.controller,
    required this.focusNode,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tags',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAdd(),
                decoration: InputDecoration(
                  hintText: 'e.g. freelance, emi, reimbursable',
                  hintStyle: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: AppTheme.textSecondary.withAlpha(80)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.all(10),
              ),
            ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags
                .map(
                  (tag) => Chip(
                    label: Text(
                      tag,
                      style: const TextStyle(fontSize: 12),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => onRemove(tag),
                    backgroundColor: AppTheme.primaryGreen.withAlpha(30),
                    deleteIconColor: AppTheme.primaryGreen,
                    side: BorderSide(
                        color: AppTheme.primaryGreen.withAlpha(80)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}
