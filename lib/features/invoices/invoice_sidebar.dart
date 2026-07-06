import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/invoice.dart';
import '../../providers/invoice_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/newsprint_primitives.dart';

final usdFormat = NumberFormat.currency(symbol: '\u0024', decimalDigits: 2);
final currencyFormat = NumberFormat.currency(symbol: 'INR ', decimalDigits: 0, locale: 'en_IN');

class InvoiceSidebar extends ConsumerWidget {
  const InvoiceSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoiceProvider);

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.88,
      backgroundColor: AppTheme.scaffold,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: invoicesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: NewsprintNotice(
                icon: Icons.error_outline_rounded,
                title: 'Invoice desk offline',
                message: '$e',
                color: AppTheme.redAccent,
              ),
            ),
            data: (invoices) {
              final totalInvoiced = invoices.fold(0.0, (s, i) => s + i.invoicedUsd);
              final totalReceived = invoices.fold(0.0, (s, i) => s + i.totalReceived);
              final totalOutstanding = totalInvoiced - totalReceived;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NewsprintPanel(
                    color: AppTheme.ink,
                    accentTop: true,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'INVOICE DESK',
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      color: AppTheme.paper,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Freelance exposure, cash received, and what is still outstanding.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppTheme.paperMuted,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, color: AppTheme.paper),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _Summary(label: 'Invoiced', amount: usdFormat.format(totalInvoiced), color: AppTheme.accentGold)),
                      const SizedBox(width: 8),
                      Expanded(child: _Summary(label: 'Received', amount: usdFormat.format(totalReceived), color: AppTheme.primaryGreen)),
                      const SizedBox(width: 8),
                      Expanded(child: _Summary(label: 'Open', amount: usdFormat.format(totalOutstanding), color: totalOutstanding > 0 ? AppTheme.redAccent : AppTheme.ink)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: () => _showAddInvoiceDialog(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('ADD INVOICE'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: invoices.isEmpty
                        ? const EmptyState(
                            icon: Icons.request_quote_rounded,
                            title: 'No invoices',
                            subtitle: 'Add an invoice to track open freelance revenue and payout splits.',
                          )
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: invoices.length,
                            itemBuilder: (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _InvoiceCard(invoice: invoices[index]),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _showAddInvoiceDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => const _AddInvoiceDialog(),
    );
  }
}

class _AddInvoiceDialog extends ConsumerStatefulWidget {
  const _AddInvoiceDialog();

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
              decoration: const InputDecoration(labelText: 'Invoiced Amount (USD) *'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _paypalCtrl,
              decoration: const InputDecoration(labelText: 'Received via PayPal (USD)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bankCtrl,
              decoration: const InputDecoration(labelText: 'Received in Bank (USD)'),
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('SAVE'),
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
  const _Summary({required this.label, required this.amount, required this.color});

  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return NewsprintPanel(
      color: AppTheme.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Text(
            amount,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontFamilyFallback: AppTheme.monoFallback,
                ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    return NewsprintPanel(
      color: AppTheme.paper,
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
                    Text(invoice.client, style: Theme.of(context).textTheme.titleLarge),
                    if (invoice.description != null) ...[
                      const SizedBox(height: 4),
                      Text(invoice.description!, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
              NewsprintTag(
                label: invoice.computedStatus,
                backgroundColor: _statusColor(invoice.computedStatus),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              NewsprintMetricStrip(label: 'Invoiced', value: usdFormat.format(invoice.invoicedUsd), valueColor: AppTheme.accentGold),
              NewsprintMetricStrip(label: 'PayPal', value: usdFormat.format(invoice.receivedPaypal), valueColor: AppTheme.primaryGreen),
              NewsprintMetricStrip(label: 'Bank', value: usdFormat.format(invoice.receivedBank), valueColor: AppTheme.focusBlue),
            ],
          ),
          if (invoice.outstanding > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Outstanding: ${usdFormat.format(invoice.outstanding)}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.redAccent),
            ),
          ],
          if (invoice.fxRate != null || invoice.paypalFee != null || invoice.fxLoss != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (invoice.fxRate != null)
                  NewsprintTag(label: 'FX INR ${invoice.fxRate!.toStringAsFixed(2)}', backgroundColor: AppTheme.paperAlt, textColor: AppTheme.ink),
                if (invoice.paypalFee != null)
                  NewsprintTag(label: 'FEE ${usdFormat.format(invoice.paypalFee!)}', backgroundColor: AppTheme.paperAlt, textColor: AppTheme.ink),
                if (invoice.fxLoss != null)
                  NewsprintTag(label: 'LOSS ${currencyFormat.format(invoice.fxLoss!)}', backgroundColor: AppTheme.paperAlt, textColor: AppTheme.ink),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return AppTheme.primaryGreen;
      case 'partial':
        return AppTheme.accentGold;
      default:
        return AppTheme.redAccent;
    }
  }
}
