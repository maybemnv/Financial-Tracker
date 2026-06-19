import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get claudeApiKey => dotenv.env['CLAUDE_API_KEY'] ?? '';
  static const String claudeApiUrl = 'https://api.anthropic.com/v1/messages';
  static const String appName = 'Finance Tracker';
  static const List<String> categories = [
    'Food', 'Travel', 'Shopping', 'Work', 'Family', 'Health', 'Subscriptions', 'Other',
  ];
}
