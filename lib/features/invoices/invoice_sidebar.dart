import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/invoice.dart';
import '../../providers/invoice_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/newsprint_primitives.dart';

final usdFormat = NumberFormat.currency(symbol: '\u0024', decimalDigits: 2);
final inrFormat = NumberFormat.currency(
  symbol: '\u20B9',
  decimalDigits: 2,
  locale: 'en_IN',
);

class InvoiceSidebar extends ConsumerWidget {
  const InvoiceSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoiceProvider);

    return Drawer(
      width: math.min(MediaQuery.of(context).size.width * 0.88, 560),
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
              final totalInvoiced =
                  invoices.fold(0.0, (s, i) => s + i.invoicedUsd);
              final totalPayPal =
                  invoices.fold(0.0, (s, i) => s + i.receivedPaypal);
              final totalInBank =
                  invoices.fold(0.0, (s, i) => s + i.receivedBank);
              final totalDifference =
                  invoices.fold(0.0, (s, i) => s + i.difference);

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
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      color: AppTheme.paper,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Freelance exposure, PayPal receipts, INR bank settlements, and what is still outstanding.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: AppTheme.paperMuted,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded,
                              color: AppTheme.paper),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: 160,
                        child: _Summary(
                          label: 'Invoiced',
                          amount: usdFormat.format(totalInvoiced),
                          color: AppTheme.accentGold,
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: _Summary(
                          label: 'PayPal',
                          amount: usdFormat.format(totalPayPal),
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: _Summary(
                          label: 'In Bank',
                          amount: inrFormat.format(totalInBank),
                          color: AppTheme.focusBlue,
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: _Summary(
                          label: 'Difference',
                          amount: usdFormat.format(totalDifference),
                          color: totalDifference > 0
                              ? AppTheme.redAccent
                              : AppTheme.primaryGreen,
                        ),
                      ),
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
                            subtitle:
                                'Add an invoice to track USD billing, PayPal receipts, and INR bank settlements.',
                          )
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: invoices.length,
                            itemBuilder: (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _InvoiceCard(
                                invoice: invoices[index],
                                onEdit: () => _showEditInvoiceDialog(
                                  context,
                                  invoices[index],
                                ),
                                onDelete: () => _confirmDelete(
                                  context,
                                  ref,
                                  invoices[index],
                                ),
                              ),
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
      builder: (ctx) => const _InvoiceDialog(),
    );
  }

  void _showEditInvoiceDialog(BuildContext context, Invoice invoice) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _InvoiceDialog(invoice: invoice),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Invoice invoice,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete invoice?'),
        content: const Text(
          'This soft-deletes the invoice. It stays in your audit history but will not appear in the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && invoice.id != null) {
      await ref.read(invoiceProvider.notifier).delete(invoice.id!);
    }
  }
}

class _InvoiceDialog extends ConsumerStatefulWidget {
  const _InvoiceDialog({this.invoice});

  final Invoice? invoice;

  @override
  ConsumerState<_InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends ConsumerState<_InvoiceDialog> {
  late final TextEditingController _clientCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _paypalCtrl;
  late final TextEditingController _bankCtrl;
  late final TextEditingController _fxRateCtrl;
  late DateTime _invoiceDate;
  bool _isSaving = false;

  bool get _isEditing => widget.invoice != null;

  @override
  void initState() {
    super.initState();
    final invoice = widget.invoice;
    _clientCtrl = TextEditingController(text: invoice?.client ?? '');
    _descCtrl = TextEditingController(text: invoice?.description ?? '');
    _amountCtrl =
        TextEditingController(text: invoice?.invoicedUsd.toString() ?? '');
    _paypalCtrl =
        TextEditingController(text: invoice?.receivedPaypal.toString() ?? '');
    _bankCtrl =
        TextEditingController(text: invoice?.receivedBank.toString() ?? '');
    _fxRateCtrl =
        TextEditingController(text: invoice?.fxRate?.toString() ?? '');
    _invoiceDate = invoice?.invoiceDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _paypalCtrl.dispose();
    _bankCtrl.dispose();
    _fxRateCtrl.dispose();
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
      title: Text(_isEditing ? 'Edit Invoice' : 'New Invoice'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _clientCtrl,
              decoration: const InputDecoration(labelText: 'Client *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              decoration:
                  const InputDecoration(labelText: 'Invoiced Amount (USD) *'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _paypalCtrl,
              decoration:
                  const InputDecoration(labelText: 'Received via PayPal (USD)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bankCtrl,
              decoration:
                  const InputDecoration(labelText: 'Received in Bank (INR)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fxRateCtrl,
              decoration: const InputDecoration(
                labelText: 'FX Rate (INR per USD)',
                helperText:
                    'Used to compare INR bank receipts with USD invoices.',
              ),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEditing ? 'UPDATE' : 'SAVE'),
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

    final paypal = double.tryParse(_paypalCtrl.text) ?? 0;
    final bank = double.tryParse(_bankCtrl.text) ?? 0;
    final fxRateText = _fxRateCtrl.text.trim();
    final fxRate = fxRateText.isEmpty
        ? widget.invoice?.fxRate
        : double.tryParse(fxRateText);

    if (fxRateText.isNotEmpty && fxRate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid FX rate')),
      );
      return;
    }

    if (!_isEditing && bank > 0 && fxRate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('FX rate is required when bank receipts are in INR'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final invoice = Invoice(
        id: widget.invoice?.id,
        client: _clientCtrl.text,
        description: _descCtrl.text.isNotEmpty ? _descCtrl.text : null,
        invoicedUsd: invoiced,
        receivedPaypal: paypal,
        receivedBank: bank,
        paypalFee: widget.invoice?.paypalFee,
        fxLoss: widget.invoice?.fxLoss,
        fxRate: fxRate,
        status: widget.invoice?.status ?? 'pending',
        invoiceDate: _invoiceDate,
        isDeleted: widget.invoice?.isDeleted ?? false,
        deletedAt: widget.invoice?.deletedAt,
        createdAt: widget.invoice?.createdAt,
        updatedAt: widget.invoice?.updatedAt,
      );

      final notifier = ref.read(invoiceProvider.notifier);
      if (_isEditing) {
        await notifier.update(invoice);
      } else {
        await notifier.add(invoice);
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

class _Summary extends StatelessWidget {
  const _Summary({
    required this.label,
    required this.amount,
    required this.color,
  });

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
          Text(label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall),
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
  const _InvoiceCard({
    required this.invoice,
    required this.onEdit,
    required this.onDelete,
  });

  final Invoice invoice;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
                    Text(invoice.client,
                        style: Theme.of(context).textTheme.titleLarge),
                    if (invoice.description != null) ...[
                      const SizedBox(height: 4),
                      Text(invoice.description!,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                icon: const Icon(Icons.more_horiz_rounded),
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
              NewsprintMetricStrip(
                label: 'Invoiced',
                value: usdFormat.format(invoice.invoicedUsd),
                valueColor: AppTheme.accentGold,
              ),
              NewsprintMetricStrip(
                label: 'PayPal',
                value: usdFormat.format(invoice.receivedPaypal),
                valueColor: AppTheme.primaryGreen,
              ),
              NewsprintMetricStrip(
                label: 'In Bank',
                value: inrFormat.format(invoice.receivedBank),
                valueColor: AppTheme.focusBlue,
              ),
              NewsprintMetricStrip(
                label: 'Difference',
                value: usdFormat.format(invoice.difference),
                valueColor: invoice.difference > 0
                    ? AppTheme.redAccent
                    : AppTheme.primaryGreen,
              ),
            ],
          ),
          if (invoice.outstanding.abs() > 0.005) ...[
            const SizedBox(height: 10),
            Text(
              invoice.difference > 0
                  ? 'Outstanding: ${usdFormat.format(invoice.outstanding)}'
                  : 'Overpaid: ${usdFormat.format(invoice.outstanding.abs())}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: invoice.difference > 0
                        ? AppTheme.redAccent
                        : AppTheme.primaryGreen,
                  ),
            ),
          ],
          if (invoice.fxRate != null ||
              invoice.paypalFee != null ||
              invoice.fxLoss != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (invoice.fxRate != null)
                  const NewsprintTag(
                    label: 'FX INR/USD ',
                    backgroundColor: AppTheme.paperAlt,
                    textColor: AppTheme.ink,
                  ),
                if (invoice.paypalFee != null)
                  NewsprintTag(
                    label: 'FEE ${usdFormat.format(invoice.paypalFee!)}',
                    backgroundColor: AppTheme.paperAlt,
                    textColor: AppTheme.ink,
                  ),
                if (invoice.fxLoss != null)
                  NewsprintTag(
                    label: 'LOSS ${inrFormat.format(invoice.fxLoss!)}',
                    backgroundColor: AppTheme.paperAlt,
                    textColor: AppTheme.ink,
                  ),
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
