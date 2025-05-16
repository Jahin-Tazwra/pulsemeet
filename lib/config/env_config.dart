import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration class for environment variables
class EnvConfig {
  /// Initialize environment variables
  static Future<void> initialize() async {
    try {
      await dotenv.load();
      debugPrint('Environment variables loaded successfully');
    } catch (e) {
      debugPrint('Error loading environment variables: $e');
    }
  }

  /// Get the Google Maps API key
  static String get googleMapsApiKey {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('Warning: GOOGLE_MAPS_API_KEY not found in .env file');
      return 'YOUR_API_KEY_HERE'; // Fallback value
    }
    return apiKey;
  }

  /// Get the Supabase URL
  static String get supabaseUrl {
    final url = dotenv.env['SUPABASE_URL'];
    if (url == null || url.isEmpty) {
      debugPrint('Warning: SUPABASE_URL not found in .env file');
      return 'https://iswssbedsqvidbafaucj.supabase.co'; // Fallback value
    }
    return url;
  }

  /// Get the Supabase anonymous key
  static String get supabaseAnonKey {
    final key = dotenv.env['SUPABASE_ANON_KEY'];
    if (key == null || key.isEmpty) {
      debugPrint('Warning: SUPABASE_ANON_KEY not found in .env file');
      // Fallback value
      return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlzd3NzYmVkc3F2aWRiYWZhdWNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDczMjA1NzEsImV4cCI6MjA2Mjg5NjU3MX0.ZlHB9ixIt5g-zmTF3vYvMp8JrFt1LvigBDzuiWnlqWY';
    }
    return key;
  }
}
