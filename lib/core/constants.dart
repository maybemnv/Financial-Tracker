import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get groqApiKey => dotenv.env['GROQ_API_KEY'] ?? '';
  static const String groqApiUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String agentModel = 'qwen/qwen3-32b';
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
