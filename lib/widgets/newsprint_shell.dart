import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';

// Hallmark - genre: editorial - macrostructure: Brutal Newsprint Workbench - design-system: design.md - designed-as-app

class NewsprintShell extends StatelessWidget {
  const NewsprintShell({
    super.key,
    required this.currentIndex,
    required this.currentLabel,
    required this.onTabSelected,
    required this.onInvoiceTap,
    required this.child,
    this.floatingActionButton,
    this.onSignOut,
  });

  final int currentIndex;
  final String currentLabel;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onInvoiceTap;
  final Widget child;
  final Widget? floatingActionButton;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEE, dd MMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      floatingActionButton: floatingActionButton,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: AppTheme.panelDecoration(
                  color: AppTheme.ink,
                  accentTop: true,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FINANCIAL TRACKER',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: AppTheme.paper,
                            fontSize: 30,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$today  |  ${currentLabel.toUpperCase()} DESK',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: AppTheme.paperMuted,
                                  letterSpacing: 1.2,
                                ),
                          ),
                        ),
                        Text(
                          'LEDGER ISSUE 01',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: AppTheme.paperMuted,
                                letterSpacing: 1.2,
                              ),
                        ),
                        if (onSignOut != null)
                          IconButton(
                            onPressed: onSignOut,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.only(left: 8),
                            constraints: const BoxConstraints(),
                            tooltip: 'Sign out',
                            icon: const Icon(Icons.logout_rounded,
                                size: 18, color: AppTheme.paperMuted),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.ink,
          border: Border(top: BorderSide(color: AppTheme.accent, width: 4)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'Ledger',
                  active: currentIndex == 0,
                  onTap: () => onTabSelected(0),
                ),
                _NavItem(
                  icon: Icons.auto_graph_rounded,
                  label: 'Briefing',
                  active: currentIndex == 1,
                  onTap: () => onTabSelected(1),
                ),
                _NavItem(
                  icon: Icons.flag_rounded,
                  label: 'Targets',
                  active: currentIndex == 2,
                  onTap: () => onTabSelected(2),
                ),
                _NavItem(
                  icon: Icons.forum_rounded,
                  label: 'Desk',
                  active: currentIndex == 3,
                  onTap: () => onTabSelected(3),
                ),
                _NavItem(
                  icon: Icons.request_quote_rounded,
                  label: 'Invoices',
                  active: false,
                  onTap: onInvoiceTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = active ? AppTheme.paper : Colors.transparent;
    final foreground = active ? AppTheme.ink : AppTheme.paper;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: background,
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                border: Border.all(
                  color: active ? AppTheme.paper : AppTheme.paperMuted,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: foreground),
                  const SizedBox(height: 4),
                  Text(
                    label.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: foreground,
                          letterSpacing: 0.9,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
