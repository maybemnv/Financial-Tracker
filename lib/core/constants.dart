import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get geminiApiKey => dotenv.env['GEMINI_API_KEY'] ?? '';
  static const String geminiApiUrl =
      'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';
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
