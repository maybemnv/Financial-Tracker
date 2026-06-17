import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'features/transactions/transaction_list_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/agent/agent_chat_screen.dart';
import 'features/invoices/invoice_sidebar.dart';

class AuraModeApp extends StatefulWidget {
  const AuraModeApp({super.key});

  @override
  State<AuraModeApp> createState() => _AuraModeAppState();
}

class _AuraModeAppState extends State<AuraModeApp> {
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
            _openInvoiceSidebar();
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
    );
  }

  void _openInvoiceSidebar() {
    Scaffold.of(context).openEndDrawer();
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: const InvoiceSidebar(),
      body: const AuraModeApp(),
    );
  }
}
