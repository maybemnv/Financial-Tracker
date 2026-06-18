import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/invoice.dart';
import '../../providers/invoice_provider.dart';
import '../../widgets/empty_state.dart';

final usdFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

class InvoiceSidebar extends ConsumerWidget {
  const InvoiceSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoiceProvider);

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Invoices'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showAddInvoiceDialog(context, ref),
            ),
          ],
        ),
        body: invoicesAsync.when(
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
                  onPressed: () => ref.read(invoiceProvider.notifier).load(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (invoices) {
            if (invoices.isEmpty) {
              return const EmptyState(
                icon: Icons.receipt_long,
                title: 'No invoices',
                subtitle: 'Tap + to add an invoice',
              );
            }

            final totalInvoiced = invoices.fold(0.0, (s, i) => s + i.invoicedUsd);
            final totalReceived = invoices.fold(0.0, (s, i) => s + i.totalReceived);
            final totalOutstanding = totalInvoiced - totalReceived;

            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: AppTheme.darkCard,
                  child: Row(
                    children: [
                      _Summary(label: 'Invoiced', amount: usdFormat.format(totalInvoiced), color: AppTheme.accentGold),
                      const SizedBox(width: 12),
                      _Summary(label: 'Received', amount: usdFormat.format(totalReceived), color: AppTheme.primaryGreen),
                      const SizedBox(width: 12),
                      _Summary(label: 'Outstanding', amount: usdFormat.format(totalOutstanding), color: totalOutstanding > 0 ? AppTheme.redAccent : AppTheme.primaryGreen),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: invoices.length,
                    itemBuilder: (context, index) => _InvoiceCard(invoice: invoices[index]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showAddInvoiceDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _AddInvoiceDialog(),
    );
  }
}

class _AddInvoiceDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AddInvoiceDialog> createState() => _AddInvoiceDialogState();
}

class _AddInvoiceDialogState extends ConsumerState<_AddInvoiceDialog> {
  final _clientCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _paypalCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  DateTime _invoiceDate = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _clientCtrl.dispose();
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _paypalCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _invoiceDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Invoice'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _clientCtrl, decoration: const InputDecoration(labelText: 'Client *')),
            const SizedBox(height: 12),
            TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              decoration: const InputDecoration(labelText: 'Invoiced Amount ($) *'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _paypalCtrl,
              decoration: const InputDecoration(labelText: 'Received via PayPal ($)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bankCtrl,
              decoration: const InputDecoration(labelText: 'Received in Bank ($)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Invoice Date'),
                child: Text(DateFormat('dd MMM yyyy').format(_invoiceDate)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_clientCtrl.text.isEmpty || _amountCtrl.text.isEmpty) return;
    final invoiced = double.tryParse(_amountCtrl.text);
    if (invoiced == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid invoiced amount')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref.read(invoiceProvider.notifier).add(Invoice(
        client: _clientCtrl.text,
        description: _descCtrl.text.isNotEmpty ? _descCtrl.text : null,
        invoicedUsd: invoiced,
        receivedPaypal: double.tryParse(_paypalCtrl.text) ?? 0,
        receivedBank: double.tryParse(_bankCtrl.text) ?? 0,
        invoiceDate: _invoiceDate,
      ));
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

class _Summary extends StatelessWidget {
  final String label;
  final String amount;
  final Color color;
  const _Summary({required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          Text(amount, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final Invoice invoice;
  const _InvoiceCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(invoice.client, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statusColor(invoice.computedStatus).withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(invoice.computedStatus.toUpperCase(), style: TextStyle(fontSize: 11, color: _statusColor(invoice.computedStatus), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if (invoice.description != null) ...[
              const SizedBox(height: 4),
              Text(invoice.description!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _RowItem(label: 'Invoiced', amount: usdFormat.format(invoice.invoicedUsd), color: AppTheme.accentGold),
                const SizedBox(width: 16),
                _RowItem(label: 'PayPal', amount: usdFormat.format(invoice.receivedPaypal), color: AppTheme.primaryGreen),
                const SizedBox(width: 16),
                _RowItem(label: 'Bank', amount: usdFormat.format(invoice.receivedBank), color: Colors.cyanAccent),
              ],
            ),
            if (invoice.outstanding > 0) ...[
              const SizedBox(height: 4),
              Text('Outstanding: ${usdFormat.format(invoice.outstanding)}', style: const TextStyle(color: AppTheme.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid': return AppTheme.primaryGreen;
      case 'partial': return AppTheme.accentGold;
      default: return AppTheme.redAccent;
    }
  }
}

class _RowItem extends StatelessWidget {
  final String label;
  final String amount;
  final Color color;
  const _RowItem({required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
        const SizedBox(height: 2),
        Text(amount, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}
