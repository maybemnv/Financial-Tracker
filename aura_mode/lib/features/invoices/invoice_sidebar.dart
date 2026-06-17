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
          error: (e, _) => Center(child: Text('Error: $e')),
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
    final clientCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final paypalCtrl = TextEditingController();
    final bankCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Invoice'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: clientCtrl, decoration: const InputDecoration(labelText: 'Client')),
              const SizedBox(height: 12),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
              const SizedBox(height: 12),
              TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: 'Invoiced Amount (\$)'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              TextField(controller: paypalCtrl, decoration: const InputDecoration(labelText: 'Received via PayPal (\$)'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              TextField(controller: bankCtrl, decoration: const InputDecoration(labelText: 'Received in Bank (\$)'), keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (clientCtrl.text.isEmpty || amountCtrl.text.isEmpty) return;
              await ref.read(invoiceProvider.notifier).add(Invoice(
                client: clientCtrl.text,
                description: descCtrl.text.isNotEmpty ? descCtrl.text : null,
                invoicedUsd: double.parse(amountCtrl.text),
                receivedPaypal: paypalCtrl.text.isNotEmpty ? double.parse(paypalCtrl.text) : 0,
                receivedBank: bankCtrl.text.isNotEmpty ? double.parse(bankCtrl.text) : 0,
                invoiceDate: DateTime.now(),
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
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
