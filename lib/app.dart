import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/lifecycle_bridge.dart';
import 'core/monthly_snapshot.dart';
import 'core/theme.dart';
import 'features/agent/agent_chat_screen.dart';
import 'features/auth/auth_controller.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/invoices/invoice_sidebar.dart';
import 'features/transactions/quick_capture_sheet.dart';
import 'features/labels/label_management_screen.dart';
import 'features/transactions/transaction_list_screen.dart';
import 'providers/ledger_provider.dart';
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

  /// Tabs the owner has actually opened. An unvisited tab is never built, so
  /// its providers are never constructed and it issues no queries (TODO 7.6) —
  /// this is what keeps Briefing's full-ledger read off the startup path.
  final Set<int> _visited = {0};

  static const _labels = [
    'Ledger',
    'Briefing',
    'Analytics',
    'Targets',
    'Agent Desk',
  ];

  Widget _screenFor(int index) => switch (index) {
        0 => const TransactionListScreen(),
        1 => const DashboardScreen(),
        // A chart drill-down applies a ledger filter, then sends the owner to
        // the Ledger tab to see the rows behind the number they tapped.
        2 => AnalyticsScreen(
            onDrillDown: () => setState(() {
              _currentIndex = 0;
              _visited.add(0);
            }),
          ),
        3 => const GoalsScreen(),
        _ => const AgentChatScreen(),
      };

  @override
  Widget build(BuildContext context) {
    return NewsprintShell(
      currentIndex: _currentIndex,
      currentLabel: _labels[_currentIndex],
      onTabSelected: (index) => setState(() {
        _currentIndex = index;
        _visited.add(index);
      }),
      onInvoiceTap: widget.onInvoiceTap,
      onSignOut: widget.onSignOut,
      onManageLabels: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LabelManagementScreen()),
      ),
      floatingActionButton: _currentIndex == 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quick capture: one field for routine cash. The full form is
                // still one tap away for transfers, investments, and edits.
                FloatingActionButton.small(
                  heroTag: 'quick',
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const QuickCaptureSheet(),
                  ),
                  child: const Icon(Icons.bolt_rounded),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'full',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AddTransactionScreen()),
                  ),
                  child: const Icon(Icons.add_rounded),
                ),
              ],
            )
          : null,
      // IndexedStack keeps a visited tab's scroll position and state; the
      // placeholder means an unvisited one costs nothing until first opened.
      child: IndexedStack(
        index: _currentIndex,
        children: [
          for (var i = 0; i < _labels.length; i++)
            if (_visited.contains(i))
              _screenFor(i)
            else
              const SizedBox.shrink(),
        ],
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
  final _bridge = LifecycleBridge.create();

  @override
  void initState() {
    super.initState();
    // Best-effort prior-month snapshot backfill, now that an owner session
    // exists (moved out of pre-auth boot so it runs under owner-scoped RLS).
    MonthlySnapshotJob.runIfNeeded();

    // Tell the JS watchdog the app is alive once the owner shell has actually
    // painted a frame — reaching here means auth already succeeded.
    afterNextFrame(_bridge.signalReady);
    _bridge.onResume(_onResume);
  }

  /// Revalidate on a healthy foreground/resume, in place, without a reload.
  ///
  /// Refreshes the session BEFORE any owner-scoped request, so an expired token
  /// surfaces as re-auth rather than a wall of RLS errors; then recreates only
  /// stale Realtime channels and refetches the paged ledger the visible tabs
  /// read from. Everything else revalidates lazily when next watched.
  Future<void> _onResume() async {
    await ref.read(authControllerProvider.notifier).refreshOwner();
    if (!mounted) return;
    ref.read(ledgerProvider.notifier)
      ..resubscribe()
      ..refresh();
  }

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
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
