import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/supabase.dart';
import 'core/monthly_snapshot.dart';
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
        theme: AppTheme.darkTheme,
        home: initError != null
            ? _ErrorScreen(initError)
            : const AppShell(),
      ),
    ),
  );
}

class _ErrorScreen extends StatelessWidget {
  final String message;
  const _ErrorScreen(this.message);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              const Text(
                'Initialization failed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
