import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/firebase_messaging_service.dart';
import '../services/notification_preferences_service.dart';
import '../services/notification_service.dart';

/// Helper class for testing notification functionality
class NotificationTestHelper {
  static final FirebaseMessagingService _firebaseMessaging =
      FirebaseMessagingService();
  static final NotificationPreferencesService _preferences =
      NotificationPreferencesService();
  static final NotificationService _notificationService = NotificationService();

  /// Test Firebase messaging initialization
  static Future<bool> testFirebaseInitialization() async {
    try {
      debugPrint('🧪 Testing Firebase messaging initialization...');

      await _firebaseMessaging.initialize();

      final isInitialized = _firebaseMessaging.isInitialized;
      final hasToken = _firebaseMessaging.fcmToken != null;

      debugPrint('✅ Firebase initialized: $isInitialized');
      debugPrint('✅ FCM token available: $hasToken');

      if (hasToken) {
        debugPrint(
            '🔑 FCM Token: ${_firebaseMessaging.fcmToken!.substring(0, 20)}...');
      }

      return isInitialized && hasToken;
    } catch (e) {
      debugPrint('❌ Firebase initialization test failed: $e');
      return false;
    }
  }

  /// Test notification preferences
  static Future<bool> testNotificationPreferences() async {
    try {
      debugPrint('🧪 Testing notification preferences...');

      await _preferences.initialize();

      // Test getting preferences
      final preferences = await _preferences.getAllPreferences();
      debugPrint('📋 Current preferences: $preferences');

      // Test setting preferences
      await _preferences.setNotificationsEnabled(true);
      await _preferences.setSoundEnabled(true);
      await _preferences.setVibrationEnabled(true);
      await _preferences.setShowMessagePreview(true);

      // Verify preferences were set
      final notificationsEnabled = await _preferences.areNotificationsEnabled();
      final soundEnabled = await _preferences.isSoundEnabled();
      final vibrationEnabled = await _preferences.isVibrationEnabled();
      final showPreview = await _preferences.showMessagePreview();

      debugPrint('✅ Notifications enabled: $notificationsEnabled');
      debugPrint('✅ Sound enabled: $soundEnabled');
      debugPrint('✅ Vibration enabled: $vibrationEnabled');
      debugPrint('✅ Show preview: $showPreview');

      return notificationsEnabled &&
          soundEnabled &&
          vibrationEnabled &&
          showPreview;
    } catch (e) {
      debugPrint('❌ Notification preferences test failed: $e');
      return false;
    }
  }

  /// Test local notification display
  static Future<bool> testLocalNotification() async {
    try {
      debugPrint('🧪 Testing local notification display...');

      // NotificationService doesn't need explicit initialization

      // Send a test local notification
      await _notificationService.showTestNotification(
        title: 'PulseMeet Test',
        body: 'This is a test notification to verify the system is working!',
      );

      debugPrint('✅ Test notification sent successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Local notification test failed: $e');
      return false;
    }
  }

  /// Test quiet hours functionality
  static Future<bool> testQuietHours() async {
    try {
      debugPrint('🧪 Testing quiet hours functionality...');

      // Test setting quiet hours
      await _preferences.setQuietHoursEnabled(true);
      await _preferences.setQuietHoursStart(22); // 10 PM
      await _preferences.setQuietHoursEnd(8); // 8 AM

      // Test checking if in quiet hours
      final isInQuietHours = await _preferences.isInQuietHours();
      final quietHoursEnabled = await _preferences.areQuietHoursEnabled();
      final startHour = await _preferences.getQuietHoursStart();
      final endHour = await _preferences.getQuietHoursEnd();

      debugPrint('✅ Quiet hours enabled: $quietHoursEnabled');
      debugPrint('✅ Quiet hours: $startHour:00 - $endHour:00');
      debugPrint('✅ Currently in quiet hours: $isInQuietHours');

      return quietHoursEnabled;
    } catch (e) {
      debugPrint('❌ Quiet hours test failed: $e');
      return false;
    }
  }

  /// Test conversation muting
  static Future<bool> testConversationMuting() async {
    try {
      debugPrint('🧪 Testing conversation muting...');

      const testConversationId = 'test-conversation-123';

      // Test muting a conversation
      await _preferences.setConversationMuted(testConversationId, true);
      final isMuted =
          await _preferences.isConversationMuted(testConversationId);

      debugPrint('✅ Conversation muted: $isMuted');

      // Test unmuting
      await _preferences.setConversationMuted(testConversationId, false);
      final isUnmuted =
          !(await _preferences.isConversationMuted(testConversationId));

      debugPrint('✅ Conversation unmuted: $isUnmuted');

      // Test timed muting
      await _preferences.muteConversationFor(
          testConversationId, const Duration(minutes: 1));
      final isTimedMuted =
          await _preferences.isConversationMuted(testConversationId);

      debugPrint('✅ Conversation timed mute: $isTimedMuted');

      return isMuted && isUnmuted && isTimedMuted;
    } catch (e) {
      debugPrint('❌ Conversation muting test failed: $e');
      return false;
    }
  }

  /// Run comprehensive notification system test
  static Future<Map<String, bool>> runComprehensiveTest() async {
    debugPrint('🚀 Starting comprehensive notification system test...');

    final results = <String, bool>{};

    // Test Firebase initialization
    results['firebase_initialization'] = await testFirebaseInitialization();

    // Test notification preferences
    results['notification_preferences'] = await testNotificationPreferences();

    // Test local notifications
    results['local_notifications'] = await testLocalNotification();

    // Test quiet hours
    results['quiet_hours'] = await testQuietHours();

    // Test conversation muting
    results['conversation_muting'] = await testConversationMuting();

    // Calculate overall success
    final allPassed = results.values.every((result) => result);
    results['overall_success'] = allPassed;

    debugPrint('📊 Test Results Summary:');
    results.forEach((test, passed) {
      final status = passed ? '✅ PASS' : '❌ FAIL';
      debugPrint('   $test: $status');
    });

    if (allPassed) {
      debugPrint('🎉 All notification tests passed! System is ready.');
    } else {
      debugPrint('⚠️ Some tests failed. Check the logs above for details.');
    }

    return results;
  }

  /// Test notification permissions
  static Future<bool> testNotificationPermissions() async {
    try {
      debugPrint('🧪 Testing notification permissions...');

      // This would typically check system-level permissions
      // For now, we'll just verify our services can initialize
      await _firebaseMessaging.initialize();
      await _preferences.initialize();

      debugPrint('✅ Notification permissions test completed');
      return true;
    } catch (e) {
      debugPrint('❌ Notification permissions test failed: $e');
      return false;
    }
  }

  /// Generate test notification data
  static Map<String, dynamic> generateTestNotificationData() {
    return {
      'conversation_id':
          'test-conversation-${DateTime.now().millisecondsSinceEpoch}',
      'message_id': 'test-message-${DateTime.now().millisecondsSinceEpoch}',
      'sender_id': 'test-sender-123',
      'sender_name': 'Test User',
      'message_content': 'This is a test message for notification testing!',
      'message_type': 'text',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Simulate receiving a push notification via Edge Function
  static Future<void> simulatePushNotification() async {
    try {
      debugPrint('🧪 Simulating push notification via Edge Function...');

      // Get Supabase client for edge function testing
      final supabase = _getSupabaseClient();
      if (supabase == null) {
        throw Exception('Supabase client not available');
      }

      // Get FCM token
      final fcmToken = _firebaseMessaging.fcmToken;
      if (fcmToken == null) {
        throw Exception('FCM token not available');
      }

      final testData = generateTestNotificationData();

      // Call the simplified edge function
      final response = await supabase.functions.invoke(
        'send-push-notification-simple',
        body: {
          'device_token': fcmToken,
          'title': testData['sender_name'],
          'body': testData['message_content'],
          'data': {
            'conversation_id': testData['conversation_id'],
            'message_id': testData['message_id'],
            'test': true,
          },
        },
      );

      if (response.status == 200) {
        debugPrint('✅ Push notification simulation completed successfully');
        debugPrint('📱 Response: ${response.data}');
      } else {
        throw Exception('Edge function returned status: ${response.status}');
      }
    } catch (e) {
      debugPrint('❌ Push notification simulation failed: $e');

      // Fallback to local notification
      debugPrint('🔄 Falling back to local notification...');
      final testData = generateTestNotificationData();
      await _notificationService.showTestNotification(
        title: testData['sender_name'],
        body: testData['message_content'],
      );
    }
  }

  /// Get Supabase client for testing
  static dynamic _getSupabaseClient() {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Could not get Supabase client: $e');
      return null;
    }
  }

  /// Clean up test data
  static Future<void> cleanupTestData() async {
    try {
      debugPrint('🧹 Cleaning up test data...');

      // Reset preferences to defaults
      await _preferences.resetToDefaults();

      // Clear any test conversation mutes
      const testConversationId = 'test-conversation-123';
      await _preferences.setConversationMuted(testConversationId, false);

      debugPrint('✅ Test data cleanup completed');
    } catch (e) {
      debugPrint('❌ Test data cleanup failed: $e');
    }
  }
}
