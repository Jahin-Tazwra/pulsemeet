import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/firebase_messaging_service.dart';

/// Helper class for debugging and getting tokens
class DebugHelper {
  static final _supabase = Supabase.instance.client;

  /// Get current auth token for testing
  static Future<String?> getAuthToken() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session?.accessToken != null) {
        debugPrint('🔑 Auth Token: Bearer ${session!.accessToken}');
        return 'Bearer ${session.accessToken}';
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting auth token: $e');
      return null;
    }
  }

  /// Get FCM token for testing
  static Future<String?> getFCMToken() async {
    try {
      final firebaseMessaging = FirebaseMessagingService();
      final token = firebaseMessaging.fcmToken;
      if (token != null) {
        debugPrint('📱 FCM Token: $token');
        return token;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting FCM token: $e');
      return null;
    }
  }

  /// Print all debug information
  static Future<void> printDebugInfo() async {
    debugPrint('🔍 === DEBUG INFORMATION ===');

    // Auth info
    final authToken = await getAuthToken();
    debugPrint('🔑 Auth Token: ${authToken ?? 'Not available'}');

    // FCM token
    final fcmToken = await getFCMToken();
    debugPrint('📱 FCM Token: ${fcmToken ?? 'Not available'}');

    // User info
    final user = _supabase.auth.currentUser;
    debugPrint('👤 User ID: ${user?.id ?? 'Not authenticated'}');
    debugPrint('📧 User Email: ${user?.email ?? 'Not available'}');

    // Supabase info
    debugPrint('🗄️ Supabase URL: ${_supabase.supabaseUrl}');
    debugPrint('🔑 Supabase Key: ${_supabase.supabaseKey.substring(0, 20)}...');

    debugPrint('🔍 === END DEBUG INFO ===');
  }

  /// Test notification with current user data
  static Future<void> testNotificationWithCurrentUser() async {
    try {
      debugPrint('🧪 Testing notification with current user...');

      final authToken = await getAuthToken();
      final fcmToken = await getFCMToken();

      if (authToken == null || fcmToken == null) {
        debugPrint('❌ Missing auth token or FCM token');
        return;
      }

      // Call the edge function
      final response = await _supabase.functions.invoke(
        'send-push-notification-simple',
        body: {
          'device_token': fcmToken,
          'title': 'PulseMeet Debug Test',
          'body': 'This is a debug test notification! 🧪',
          'data': {
            'debug': true,
            'timestamp': DateTime.now().toIso8601String(),
          },
        },
      );

      if (response.status == 200) {
        debugPrint('✅ Test notification sent successfully!');
        debugPrint('📱 Response: ${response.data}');
      } else {
        debugPrint('❌ Test notification failed: ${response.status}');
        debugPrint('📱 Error: ${response.data}');
      }
    } catch (e) {
      debugPrint('❌ Error testing notification: $e');
    }
  }

  /// Copy debug info to clipboard (for easy sharing)
  static Future<Map<String, String?>> getDebugInfoMap() async {
    return {
      'auth_token': await getAuthToken(),
      'fcm_token': await getFCMToken(),
      'user_id': _supabase.auth.currentUser?.id,
      'user_email': _supabase.auth.currentUser?.email,
      'supabase_url': _supabase.supabaseUrl,
      'supabase_key': '${_supabase.supabaseKey.substring(0, 20)}...',
    };
  }
}
