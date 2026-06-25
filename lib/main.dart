import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/supabase.dart';
import 'core/monthly_snapshot.dart';
import 'core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  SupabaseService(); // ensure singleton
  try {
    await SupabaseService().init();
    // Best-effort: backfill last month's snapshot on launch of a new month.
    // Never blocks or crashes the app on failure.
    MonthlySnapshotJob.runIfNeeded();
  } catch (e) {
    // Initialization failure surfaces as an error state in the UI.
    debugPrint('Supabase init failed: $e');
  }

  runApp(
    ProviderScope(
      child: MaterialApp(
        title: 'Finance Tracker',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const AppShell(),
      ),
    ),
  );
}
