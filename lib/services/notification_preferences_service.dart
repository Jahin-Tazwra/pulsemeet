import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for managing notification preferences
class NotificationPreferencesService {
  static final NotificationPreferencesService _instance = NotificationPreferencesService._internal();
  factory NotificationPreferencesService() => _instance;
  NotificationPreferencesService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  SharedPreferences? _prefs;

  // Preference keys
  static const String _notificationsEnabledKey = 'notifications_enabled';
  static const String _soundEnabledKey = 'notification_sound_enabled';
  static const String _vibrationEnabledKey = 'notification_vibration_enabled';
  static const String _showPreviewKey = 'notification_show_preview';
  static const String _quietHoursEnabledKey = 'quiet_hours_enabled';
  static const String _quietHoursStartKey = 'quiet_hours_start';
  static const String _quietHoursEndKey = 'quiet_hours_end';
  static const String _conversationMutedPrefix = 'conversation_muted_';

  /// Initialize the service
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      debugPrint('✅ Notification preferences service initialized');
    } catch (e) {
      debugPrint('❌ Error initializing notification preferences: $e');
    }
  }

  /// Check if notifications are enabled globally
  Future<bool> areNotificationsEnabled() async {
    if (_prefs == null) await initialize();
    return _prefs?.getBool(_notificationsEnabledKey) ?? true;
  }

  /// Set global notification enabled state
  Future<void> setNotificationsEnabled(bool enabled) async {
    if (_prefs == null) await initialize();
    await _prefs?.setBool(_notificationsEnabledKey, enabled);
    debugPrint('🔔 Global notifications ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Check if sound is enabled
  Future<bool> isSoundEnabled() async {
    if (_prefs == null) await initialize();
    return _prefs?.getBool(_soundEnabledKey) ?? true;
  }

  /// Set sound enabled state
  Future<void> setSoundEnabled(bool enabled) async {
    if (_prefs == null) await initialize();
    await _prefs?.setBool(_soundEnabledKey, enabled);
    debugPrint('🔊 Notification sound ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Check if vibration is enabled
  Future<bool> isVibrationEnabled() async {
    if (_prefs == null) await initialize();
    return _prefs?.getBool(_vibrationEnabledKey) ?? true;
  }

  /// Set vibration enabled state
  Future<void> setVibrationEnabled(bool enabled) async {
    if (_prefs == null) await initialize();
    await _prefs?.setBool(_vibrationEnabledKey, enabled);
    debugPrint('📳 Notification vibration ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Check if message preview should be shown
  Future<bool> showMessagePreview() async {
    if (_prefs == null) await initialize();
    return _prefs?.getBool(_showPreviewKey) ?? true;
  }

  /// Set message preview enabled state
  Future<void> setShowMessagePreview(bool enabled) async {
    if (_prefs == null) await initialize();
    await _prefs?.setBool(_showPreviewKey, enabled);
    debugPrint('👁️ Message preview ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Check if quiet hours are enabled
  Future<bool> areQuietHoursEnabled() async {
    if (_prefs == null) await initialize();
    return _prefs?.getBool(_quietHoursEnabledKey) ?? false;
  }

  /// Set quiet hours enabled state
  Future<void> setQuietHoursEnabled(bool enabled) async {
    if (_prefs == null) await initialize();
    await _prefs?.setBool(_quietHoursEnabledKey, enabled);
    debugPrint('🌙 Quiet hours ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Get quiet hours start time (24-hour format, e.g., 22 for 10 PM)
  Future<int> getQuietHoursStart() async {
    if (_prefs == null) await initialize();
    return _prefs?.getInt(_quietHoursStartKey) ?? 22; // Default: 10 PM
  }

  /// Set quiet hours start time
  Future<void> setQuietHoursStart(int hour) async {
    if (_prefs == null) await initialize();
    await _prefs?.setInt(_quietHoursStartKey, hour);
    debugPrint('🌙 Quiet hours start set to: ${hour}:00');
  }

  /// Get quiet hours end time (24-hour format, e.g., 8 for 8 AM)
  Future<int> getQuietHoursEnd() async {
    if (_prefs == null) await initialize();
    return _prefs?.getInt(_quietHoursEndKey) ?? 8; // Default: 8 AM
  }

  /// Set quiet hours end time
  Future<void> setQuietHoursEnd(int hour) async {
    if (_prefs == null) await initialize();
    await _prefs?.setInt(_quietHoursEndKey, hour);
    debugPrint('🌙 Quiet hours end set to: ${hour}:00');
  }

  /// Check if currently in quiet hours
  Future<bool> isInQuietHours() async {
    if (!await areQuietHoursEnabled()) return false;

    final now = DateTime.now();
    final currentHour = now.hour;
    final startHour = await getQuietHoursStart();
    final endHour = await getQuietHoursEnd();

    // Handle overnight quiet hours (e.g., 22:00 to 08:00)
    if (startHour > endHour) {
      return currentHour >= startHour || currentHour < endHour;
    } else {
      // Handle same-day quiet hours (e.g., 13:00 to 15:00)
      return currentHour >= startHour && currentHour < endHour;
    }
  }

  /// Check if notifications are enabled for a specific conversation
  Future<bool> areConversationNotificationsEnabled(String conversationId) async {
    // First check global notifications
    if (!await areNotificationsEnabled()) return false;

    // Check if in quiet hours
    if (await isInQuietHours()) return false;

    // Check if conversation is muted
    if (await isConversationMuted(conversationId)) return false;

    return true;
  }

  /// Check if a conversation is muted
  Future<bool> isConversationMuted(String conversationId) async {
    if (_prefs == null) await initialize();
    return _prefs?.getBool('$_conversationMutedPrefix$conversationId') ?? false;
  }

  /// Mute/unmute a conversation
  Future<void> setConversationMuted(String conversationId, bool muted) async {
    if (_prefs == null) await initialize();
    await _prefs?.setBool('$_conversationMutedPrefix$conversationId', muted);
    debugPrint('🔇 Conversation $conversationId ${muted ? 'muted' : 'unmuted'}');

    // Also store in database for cross-device sync
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        await _supabase.from('conversation_settings').upsert({
          'user_id': userId,
          'conversation_id': conversationId,
          'is_muted': muted,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('❌ Error syncing conversation mute state: $e');
    }
  }

  /// Mute conversation for a specific duration
  Future<void> muteConversationFor(String conversationId, Duration duration) async {
    await setConversationMuted(conversationId, true);
    
    // Store unmute time
    final unmuteTime = DateTime.now().add(duration);
    if (_prefs == null) await initialize();
    await _prefs?.setString('${_conversationMutedPrefix}${conversationId}_until', unmuteTime.toIso8601String());
    
    debugPrint('🔇 Conversation $conversationId muted until: $unmuteTime');
  }

  /// Check if conversation mute has expired and unmute if necessary
  Future<void> checkAndUpdateMuteStatus(String conversationId) async {
    if (_prefs == null) await initialize();
    
    final unmuteTimeStr = _prefs?.getString('${_conversationMutedPrefix}${conversationId}_until');
    if (unmuteTimeStr != null) {
      final unmuteTime = DateTime.parse(unmuteTimeStr);
      if (DateTime.now().isAfter(unmuteTime)) {
        // Unmute the conversation
        await setConversationMuted(conversationId, false);
        await _prefs?.remove('${_conversationMutedPrefix}${conversationId}_until');
        debugPrint('🔊 Conversation $conversationId automatically unmuted');
      }
    }
  }

  /// Get all notification preferences as a map
  Future<Map<String, dynamic>> getAllPreferences() async {
    return {
      'notifications_enabled': await areNotificationsEnabled(),
      'sound_enabled': await isSoundEnabled(),
      'vibration_enabled': await isVibrationEnabled(),
      'show_preview': await showMessagePreview(),
      'quiet_hours_enabled': await areQuietHoursEnabled(),
      'quiet_hours_start': await getQuietHoursStart(),
      'quiet_hours_end': await getQuietHoursEnd(),
      'in_quiet_hours': await isInQuietHours(),
    };
  }

  /// Reset all preferences to defaults
  Future<void> resetToDefaults() async {
    if (_prefs == null) await initialize();
    
    await _prefs?.setBool(_notificationsEnabledKey, true);
    await _prefs?.setBool(_soundEnabledKey, true);
    await _prefs?.setBool(_vibrationEnabledKey, true);
    await _prefs?.setBool(_showPreviewKey, true);
    await _prefs?.setBool(_quietHoursEnabledKey, false);
    await _prefs?.setInt(_quietHoursStartKey, 22);
    await _prefs?.setInt(_quietHoursEndKey, 8);
    
    debugPrint('🔄 Notification preferences reset to defaults');
  }

  /// Sync conversation mute settings from database
  Future<void> syncConversationSettings() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await _supabase
          .from('conversation_settings')
          .select('conversation_id, is_muted')
          .eq('user_id', userId);

      if (response is List) {
        for (final setting in response) {
          final conversationId = setting['conversation_id'] as String;
          final isMuted = setting['is_muted'] as bool;
          
          if (_prefs == null) await initialize();
          await _prefs?.setBool('$_conversationMutedPrefix$conversationId', isMuted);
        }
        debugPrint('✅ Synced conversation settings from database');
      }
    } catch (e) {
      debugPrint('❌ Error syncing conversation settings: $e');
    }
  }

  /// Export preferences for backup
  Future<Map<String, dynamic>> exportPreferences() async {
    if (_prefs == null) await initialize();
    
    final keys = _prefs?.getKeys() ?? <String>{};
    final Map<String, dynamic> preferences = {};
    
    for (final key in keys) {
      if (key.startsWith('notification') || key.startsWith('quiet_hours') || key.startsWith(_conversationMutedPrefix)) {
        final value = _prefs?.get(key);
        if (value != null) {
          preferences[key] = value;
        }
      }
    }
    
    return preferences;
  }

  /// Import preferences from backup
  Future<void> importPreferences(Map<String, dynamic> preferences) async {
    if (_prefs == null) await initialize();
    
    for (final entry in preferences.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (value is bool) {
        await _prefs?.setBool(key, value);
      } else if (value is int) {
        await _prefs?.setInt(key, value);
      } else if (value is String) {
        await _prefs?.setString(key, value);
      }
    }
    
    debugPrint('✅ Imported notification preferences');
  }
}
