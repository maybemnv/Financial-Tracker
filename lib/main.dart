import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/supabase.dart';
import 'core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SupabaseService().init();
  } catch (e) {
    // Will show error state in UI
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
