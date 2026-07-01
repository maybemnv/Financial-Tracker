import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'features/sms/sms_listener.dart';
import 'features/transactions/transaction_list_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/agent/agent_chat_screen.dart';
import 'features/invoices/invoice_sidebar.dart';
import 'providers/transaction_provider.dart';

class AppTabs extends StatefulWidget {
  final VoidCallback onInvoiceTap;
  const AppTabs({super.key, required this.onInvoiceTap});

  @override
  State<AppTabs> createState() => _AppTabsState();
}

class _AppTabsState extends State<AppTabs> {
  int _currentIndex = 0;

  final _screens = const [
    TransactionListScreen(),
    DashboardScreen(),
    GoalsScreen(),
    AgentChatScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 4) {
            widget.onInvoiceTap();
          } else {
            setState(() => _currentIndex = index);
          }
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.darkSurface,
        selectedItemColor: AppTheme.primaryGreen,
        unselectedItemColor: AppTheme.textSecondary,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: 'Transactions'),
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.flag), label: 'Goals'),
          BottomNavigationBarItem(icon: Icon(Icons.smart_toy), label: 'Agent'),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long, color: AppTheme.accentGold),
            label: 'Invoices',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
              ),
              child: const Icon(Icons.add),
            )
          : null,
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
        SnackBar(content: Text('Transaction added: INR $amount at $merchant')),
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
      endDrawer: const InvoiceSidebar(),
      body: AppTabs(onInvoiceTap: () {
        _scaffoldKey.currentState?.openEndDrawer();
      }),
    );
  }
}
