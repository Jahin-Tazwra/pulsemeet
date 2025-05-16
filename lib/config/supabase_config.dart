import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'env_config.dart';

/// Configuration class for Supabase connection
class SupabaseConfig {
  /// Initialize Supabase client
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey,
      debug: kDebugMode,
      // authFlowType parameter has been removed in newer versions
    );
  }

  /// Get the Supabase client instance
  static SupabaseClient get client => Supabase.instance.client;

  /// Get the Supabase auth instance
  static GoTrueClient get auth => Supabase.instance.client.auth;

  /// Get the Supabase storage instance
  static SupabaseStorageClient get storage => Supabase.instance.client.storage;

  /// Get the Supabase realtime instance
  static RealtimeClient get realtime => Supabase.instance.client.realtime;
}
