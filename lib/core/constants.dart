import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  // The Gemini key is a server-only Supabase function secret (Phase 3). It must
  // never reach the browser bundle again — the Agent Desk talks to the `agent`
  // Edge Function, which holds the key.
  static const String agentModel = 'gemini-2.5-flash';
  static const String appName = 'Finance Tracker';
  static const List<String> categories = [
    'Food',
    'Travel',
    'Shopping',
    'Work',
    'Family',
    'Health',
    'Subscriptions',
    'Other',
  ];
}
