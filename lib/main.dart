import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/monthly_snapshot.dart';
import 'core/supabase.dart';
import 'core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? initError;

  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    initError = 'dotenv: $e';
  }

  SupabaseService();
  try {
    await SupabaseService().init();
    MonthlySnapshotJob.runIfNeeded();
  } catch (e) {
    initError ??= 'Supabase: $e';
  }

  runApp(
    ProviderScope(
      child: MaterialApp(
        title: 'Finance Tracker',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: initError != null ? _ErrorScreen(initError) : const AppShell(),
      ),
    ),
  );
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.panelDecoration(
                color: AppTheme.paper,
                accentTop: true,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Initialization failed',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The desk could not boot its data services. Review the message below before retrying.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: AppTheme.panelDecoration(color: AppTheme.paperAlt),
                    child: Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamilyFallback: AppTheme.monoFallback,
                            color: AppTheme.ink,
                          ),
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
