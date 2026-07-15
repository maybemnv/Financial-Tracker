import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/agent/agent_chat_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/invoices/invoice_sidebar.dart';
import 'features/sms/sms_listener.dart';
import 'features/transactions/transaction_list_screen.dart';
import 'providers/transaction_provider.dart';
import 'widgets/newsprint_shell.dart';

class AppTabs extends StatefulWidget {
  const AppTabs({super.key, required this.onInvoiceTap});

  final VoidCallback onInvoiceTap;

  @override
  State<AppTabs> createState() => _AppTabsState();
}

class _AppTabsState extends State<AppTabs> {
  int _currentIndex = 0;

  static const _labels = [
    'Ledger',
    'Briefing',
    'Targets',
    'Agent Desk',
  ];

  final _screens = const [
    TransactionListScreen(),
    DashboardScreen(),
    GoalsScreen(),
    AgentChatScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return NewsprintShell(
      currentIndex: _currentIndex,
      currentLabel: _labels[_currentIndex],
      onTabSelected: (index) => setState(() => _currentIndex = index),
      onInvoiceTap: widget.onInvoiceTap,
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
              ),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      child: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  StreamSubscription? _smsSubscription;

  @override
  void initState() {
    super.initState();
    _smsSubscription = SmsListener().onTransactionParsed.listen((tx) async {
      final inserted = await ref.read(transactionProvider.notifier).add(tx);
      if (!mounted || !inserted) return;
      final merchant = tx.merchant ?? tx.bank ?? 'unknown merchant';
      final amount = tx.amount == tx.amount.truncateToDouble()
          ? tx.amount.toStringAsFixed(0)
          : tx.amount.toStringAsFixed(2);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Transaction added: \u20B9$amount at $merchant')),
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      SmsListener().start();
    });
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    SmsListener().stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.scaffold,
      endDrawer: const InvoiceSidebar(),
      body: AppTabs(onInvoiceTap: () {
        _scaffoldKey.currentState?.openEndDrawer();
      }),
    );
  }
}
