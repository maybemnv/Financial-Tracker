import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/summary_card.dart';

final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2, locale: 'en_IN');

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: transactionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (transactions) => _DashboardContent(transactions: transactions),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final List<Transaction> transactions;
  const _DashboardContent({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thisMonth = transactions.where((t) =>
        t.createdAt != null &&
        t.createdAt!.month == now.month &&
        t.createdAt!.year == now.year).toList();

    final earned = thisMonth
        .where((t) => t.type == 'credit')
        .fold(0.0, (sum, t) => sum + t.amount);
    final spent = thisMonth
        .where((t) => t.type == 'debit')
        .fold(0.0, (sum, t) => sum + t.amount);
    final saved = earned - spent;

    final categoryMap = <String, double>{};
    for (final t in thisMonth.where((t) => t.type == 'debit' && t.category != null)) {
      categoryMap.update(t.category!, (v) => v + t.amount, ifAbsent: () => t.amount);
    }

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: SummaryCard(label: 'Earned', amount: currencyFormat.format(earned), color: AppTheme.primaryGreen, icon: Icons.arrow_downward)),
              const SizedBox(width: 12),
              Expanded(child: SummaryCard(label: 'Spent', amount: currencyFormat.format(spent), color: AppTheme.redAccent, icon: Icons.arrow_upward)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: SummaryCard(label: 'Saved', amount: currencyFormat.format(saved), color: saved >= 0 ? AppTheme.primaryGreen : AppTheme.redAccent, icon: Icons.savings)),
              const SizedBox(width: 12),
              Expanded(child: SummaryCard(label: 'Net', amount: currencyFormat.format(earned), color: AppTheme.accentPurple, icon: Icons.account_balance)),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Spending by Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: categoryMap.isEmpty
                ? const Center(child: Text('No spending this month', style: TextStyle(color: AppTheme.textSecondary)))
                : PieChart(
                    PieChartData(
                      sections: _buildPieSections(categoryMap),
                      centerSpaceRadius: 40,
                      sectionsSpace: 2,
                    ),
                  ),
          ),
          ...categoryMap.entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: _categoryColor(e.key), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Expanded(child: Text(e.key)),
                Text(currencyFormat.format(e.value), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections(Map<String, double> data) {
    final total = data.values.fold(0.0, (a, b) => a + b);
    final colors = [
      AppTheme.primaryGreen, AppTheme.redAccent, AppTheme.accentPurple,
      AppTheme.accentGold, Colors.cyanAccent, Colors.orangeAccent,
      Colors.pinkAccent, Colors.lightBlueAccent,
    ];
    int i = 0;
    return data.entries.map((e) {
      final pct = (e.value / total * 100).toStringAsFixed(0);
      return PieChartSectionData(
        value: e.value,
        color: colors[i++ % colors.length],
        title: '$pct%',
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        radius: 50,
      );
    }).toList();
  }

  Color _categoryColor(String cat) {
    const colors = {
      'Food': AppTheme.primaryGreen,
      'Travel': Colors.cyanAccent,
      'Shopping': AppTheme.accentPurple,
      'Work': Colors.orangeAccent,
      'Family': Colors.pinkAccent,
      'Health': AppTheme.redAccent,
      'Subscriptions': Colors.lightBlueAccent,
    };
    return colors[cat] ?? AppTheme.accentGold;
  }
}
