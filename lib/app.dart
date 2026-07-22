import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/monthly_snapshot.dart';
import 'core/theme.dart';
import 'features/agent/agent_chat_screen.dart';
import 'features/auth/auth_controller.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/invoices/invoice_sidebar.dart';
import 'features/transactions/transaction_list_screen.dart';
import 'widgets/newsprint_shell.dart';

class AppTabs extends StatefulWidget {
  const AppTabs({super.key, required this.onInvoiceTap, this.onSignOut});

  final VoidCallback onInvoiceTap;
  final VoidCallback? onSignOut;

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
      onSignOut: widget.onSignOut,
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

  @override
  void initState() {
    super.initState();
    // Best-effort prior-month snapshot backfill, now that an owner session
    // exists (moved out of pre-auth boot so it runs under owner-scoped RLS).
    MonthlySnapshotJob.runIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.scaffold,
      endDrawer: const InvoiceSidebar(),
      body: AppTabs(
        onInvoiceTap: () => _scaffoldKey.currentState?.openEndDrawer(),
        onSignOut: () => ref.read(authControllerProvider.notifier).signOut(),
      ),
    );
  }
}
