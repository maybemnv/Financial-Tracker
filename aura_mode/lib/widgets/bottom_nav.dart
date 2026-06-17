import 'package:flutter/material.dart';
import '../core/theme.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onInvoiceTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onInvoiceTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
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
    );
  }
}
