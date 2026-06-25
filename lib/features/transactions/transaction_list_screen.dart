import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../models/transaction.dart';
import '../../providers/account_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/empty_state.dart';

final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2, locale: 'en_IN');

/// Index of the "All accounts" filter entry; account filters come after.
const _allAccounts = 'all';

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
          // Account filter chip row.
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
                return RefreshIndicator(
                  onRefresh: () => ref.read(transactionProvider.notifier).load(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) =>
                        _TransactionCard(tx: filtered[index]),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(30),
          child: Icon(
            isCredit
                ? Icons.arrow_downward
                : isTransfer
                    ? Icons.swap_horiz
                    : isInvestment
                        ? Icons.trending_up
                        : Icons.arrow_upward,
            color: color,
            size: 20,
          ),
        ),
        title: Text(
          tx.merchant ?? tx.vpa ?? tx.note ?? 'Unknown',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${_typeLabel(tx.type)}${tx.category != null ? ' • ${tx.category}' : ''}${tx.bank != null ? ' • ${tx.bank}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$sign${currencyFormat.format(tx.amount)}',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            if (tx.createdAt != null)
              Text(
                DateFormat('dd MMM').format(tx.createdAt!),
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
          ],
        ),
        onLongPress: () => _confirmDelete(context, ref),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'transfer':
        return 'Transfer';
      case 'investment':
        return 'Investment';
      case 'credit':
        return 'Income';
      default:
        return tx.category ?? 'Expense';
    }
  }

  /// Soft delete — gated behind an explicit confirmation. AI never deletes.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This will soft-delete the transaction. It stays in your audit history but won\'t appear in the app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
  String _type = 'debit';
  String _category = 'Other';
  String? _accountId; // source / primary account
  String? _destAccountId; // for transfer / investment destination
  bool _isSaving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    _vpaCtrl.dispose();
    super.dispose();
  }

  bool get _needsDestination => _type == 'transfer' || _type == 'investment';

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountProvider);
    final accounts = accountsAsync.maybeWhen(data: (a) => a, orElse: () => <dynamic>[]);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Transaction')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Type selector — debit / credit / transfer / investment.
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
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(labelText: 'Amount (₹)', prefixText: '₹ '),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (double.tryParse(v) == null) return 'Invalid number';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              // Account selector — which account is this from/to.
              DropdownButtonFormField<String>(
                initialValue: _accountId,
                decoration: InputDecoration(
                  labelText: _type == 'transfer'
                      ? 'From account'
                      : _type == 'investment'
                          ? 'From account'
                          : 'Account',
                ),
                items: accounts
                    .map((a) => DropdownMenuItem(value: a.id as String, child: Text(a.name as String)))
                    .toList(),
                onChanged: (v) => setState(() => _accountId = v),
                validator: (v) => v == null || v.isEmpty ? 'Select an account' : null,
              ),
              const SizedBox(height: 12),
              if (_needsDestination) ...[
                DropdownButtonFormField<String>(
                  initialValue: _destAccountId,
                  decoration: InputDecoration(
                    labelText: _type == 'transfer' ? 'To account' : 'Destination (e.g. Nifty 50 fund)',
                  ),
                  items: accounts
                      .map((a) => DropdownMenuItem(value: a.id as String, child: Text(a.name as String)))
                      .toList(),
                  onChanged: (v) => setState(() => _destAccountId = v),
                  validator: (v) => v == null || v.isEmpty ? 'Select an account' : null,
                ),
                const SizedBox(height: 12),
              ],
              // Merchant / VPA are only relevant for plain debit/credit.
              if (!_needsDestination) ...[
                TextFormField(
                  controller: _merchantCtrl,
                  decoration: const InputDecoration(labelText: 'Merchant'),
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
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _category = v!),
                ),
              ],
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
            );
      } else {
        final tx = Transaction(
          amount: amount,
          type: _type,
          accountId: _accountId,
          merchant: _merchantCtrl.text.isNotEmpty ? _merchantCtrl.text : null,
          vpa: _vpaCtrl.text.isNotEmpty ? _vpaCtrl.text : null,
          category: _needsDestination ? null : _category,
          source: 'manual',
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
