import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/empty_state.dart';

final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2, locale: 'en_IN');

class TransactionListScreen extends ConsumerWidget {
  const TransactionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: transactionsAsync.when(
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
          if (transactions.isEmpty) {
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
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final tx = transactions[index];
                return _TransactionCard(tx: tx);
              },
            ),
          );
        },
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final Transaction tx;
  const _TransactionCard({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isCredit = tx.type == 'credit';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCredit ? AppTheme.primaryGreen.withAlpha(30) : AppTheme.redAccent.withAlpha(30),
          child: Icon(
            isCredit ? Icons.arrow_downward : Icons.arrow_upward,
            color: isCredit ? AppTheme.primaryGreen : AppTheme.redAccent,
            size: 20,
          ),
        ),
        title: Text(
          tx.merchant ?? tx.vpa ?? 'Unknown',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${tx.category ?? 'Uncategorized'}${tx.bank != null ? ' • ${tx.bank}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isCredit ? '+' : '-'}${currencyFormat.format(tx.amount)}',
              style: TextStyle(
                color: isCredit ? AppTheme.primaryGreen : AppTheme.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            if (tx.createdAt != null)
              Text(
                DateFormat('dd MMM').format(tx.createdAt!),
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
          ],
        ),
      ),
    );
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
  bool _isSaving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    _vpaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Transaction')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'debit', label: Text('Debit')),
                  ButtonSegment(value: 'credit', label: Text('Credit')),
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
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: AppConstants.categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v!),
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
      final tx = Transaction(
        amount: double.parse(_amountCtrl.text),
        type: _type,
        merchant: _merchantCtrl.text.isNotEmpty ? _merchantCtrl.text : null,
        vpa: _vpaCtrl.text.isNotEmpty ? _vpaCtrl.text : null,
        category: _category,
        source: 'manual',
      );
      await ref.read(transactionProvider.notifier).add(tx);
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
