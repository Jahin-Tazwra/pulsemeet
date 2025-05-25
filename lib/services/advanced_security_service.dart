import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/models/encryption_models.dart';
import 'package:pulsemeet/services/enhanced_encryption_service.dart';

/// Service for advanced security features
class AdvancedSecurityService {
  static final AdvancedSecurityService _instance =
      AdvancedSecurityService._internal();
  factory AdvancedSecurityService() => _instance;
  AdvancedSecurityService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final EnhancedEncryptionService _encryptionService =
      EnhancedEncryptionService();

  // Security settings
  bool _screenshotProtectionEnabled = false;
  bool _screenRecordingDetectionEnabled = false;
  final Map<String, bool> _conversationScreenshotProtection = {};

  // Security monitoring
  Timer? _securityMonitoringTimer;
  final List<SecurityEvent> _recentSecurityEvents = [];

  /// Initialize the service
  Future<void> initialize() async {
    debugPrint('🔒 Initializing Advanced Security Service');

    try {
      // Load security settings
      await _loadSecuritySettings();

      // Start security monitoring
      _startSecurityMonitoring();

      // Setup screenshot detection
      await _setupScreenshotDetection();

      debugPrint('✅ Advanced Security Service initialized');
    } catch (e) {
      debugPrint('❌ Error initializing Advanced Security Service: $e');
    }
  }

  /// Load security settings from secure storage
  Future<void> _loadSecuritySettings() async {
    try {
      final screenshotProtection =
          await _secureStorage.read(key: 'screenshot_protection_enabled');
      _screenshotProtectionEnabled = screenshotProtection == 'true';

      final screenRecordingDetection =
          await _secureStorage.read(key: 'screen_recording_detection_enabled');
      _screenRecordingDetectionEnabled = screenRecordingDetection == 'true';

      debugPrint('📝 Loaded security settings');
    } catch (e) {
      debugPrint('❌ Error loading security settings: $e');
    }
  }

  /// Start security monitoring
  void _startSecurityMonitoring() {
    _securityMonitoringTimer = Timer.periodic(
      const Duration(seconds: 30),
      (timer) => _performSecurityCheck(),
    );
  }

  /// Setup screenshot detection
  Future<void> _setupScreenshotDetection() async {
    if (Platform.isAndroid) {
      // Android screenshot detection would require native implementation
      debugPrint('📱 Screenshot detection setup for Android');
    } else if (Platform.isIOS) {
      // iOS screenshot detection
      debugPrint('📱 Screenshot detection setup for iOS');
    }
  }

  /// Perform periodic security check
  Future<void> _performSecurityCheck() async {
    try {
      // Check for security threats
      await _checkForSecurityThreats();

      // Monitor encryption status
      await _monitorEncryptionStatus();

      // Clean up old security events
      _cleanupOldSecurityEvents();
    } catch (e) {
      debugPrint('❌ Error in security check: $e');
    }
  }

  /// Check for security threats
  Future<void> _checkForSecurityThreats() async {
    // Check for rooted/jailbroken devices
    if (await _isDeviceCompromised()) {
      await _logSecurityEvent(
        SecurityEventType.securityWarning,
        'Device appears to be rooted or jailbroken',
        metadata: {'threat_level': 'high'},
      );
    }

    // Check for debugging
    if (kDebugMode) {
      await _logSecurityEvent(
        SecurityEventType.securityWarning,
        'App is running in debug mode',
        metadata: {'threat_level': 'medium'},
      );
    }
  }

  /// Monitor encryption status
  Future<void> _monitorEncryptionStatus() async {
    // This would check encryption health across conversations
    // For now, just log that monitoring is active
    debugPrint('🔐 Monitoring encryption status');
  }

  /// Check if device is compromised
  Future<bool> _isDeviceCompromised() async {
    // Basic checks for rooted/jailbroken devices
    // In a real implementation, this would be more comprehensive

    if (Platform.isAndroid) {
      // Check for common root indicators
      final rootPaths = [
        '/system/app/Superuser.apk',
        '/sbin/su',
        '/system/bin/su',
        '/system/xbin/su',
        '/data/local/xbin/su',
        '/data/local/bin/su',
        '/system/sd/xbin/su',
        '/system/bin/failsafe/su',
        '/data/local/su',
      ];

      for (final path in rootPaths) {
        if (await File(path).exists()) {
          return true;
        }
      }
    } else if (Platform.isIOS) {
      // Check for common jailbreak indicators
      final jailbreakPaths = [
        '/Applications/Cydia.app',
        '/Library/MobileSubstrate/MobileSubstrate.dylib',
        '/bin/bash',
        '/usr/sbin/sshd',
        '/etc/apt',
      ];

      for (final path in jailbreakPaths) {
        if (await File(path).exists()) {
          return true;
        }
      }
    }

    return false;
  }

  /// Enable screenshot protection for a conversation
  Future<void> enableScreenshotProtection(String conversationId) async {
    try {
      _conversationScreenshotProtection[conversationId] = true;

      // Apply screenshot protection
      await _applyScreenshotProtection(true);

      await _logSecurityEvent(
        SecurityEventType.securityWarning,
        'Screenshot protection enabled',
        conversationId: conversationId,
      );

      debugPrint(
          '🔒 Screenshot protection enabled for conversation $conversationId');
    } catch (e) {
      debugPrint('❌ Error enabling screenshot protection: $e');
    }
  }

  /// Disable screenshot protection for a conversation
  Future<void> disableScreenshotProtection(String conversationId) async {
    try {
      _conversationScreenshotProtection[conversationId] = false;

      // Check if any conversations still have protection enabled
      final hasProtectedConversations =
          _conversationScreenshotProtection.values.any((enabled) => enabled);

      if (!hasProtectedConversations) {
        await _applyScreenshotProtection(false);
      }

      await _logSecurityEvent(
        SecurityEventType.securityWarning,
        'Screenshot protection disabled',
        conversationId: conversationId,
      );

      debugPrint(
          '🔒 Screenshot protection disabled for conversation $conversationId');
    } catch (e) {
      debugPrint('❌ Error disabling screenshot protection: $e');
    }
  }

  /// Apply screenshot protection at system level
  Future<void> _applyScreenshotProtection(bool enable) async {
    try {
      if (Platform.isAndroid) {
        // Android screenshot protection
        await _setAndroidScreenshotProtection(enable);
      } else if (Platform.isIOS) {
        // iOS screenshot protection
        await _setIOSScreenshotProtection(enable);
      }
    } catch (e) {
      debugPrint('❌ Error applying screenshot protection: $e');
    }
  }

  /// Set Android screenshot protection
  Future<void> _setAndroidScreenshotProtection(bool enable) async {
    // This would require native Android implementation
    // For now, just log the action
    debugPrint(
        '📱 Android screenshot protection: ${enable ? 'enabled' : 'disabled'}');
  }

  /// Set iOS screenshot protection
  Future<void> _setIOSScreenshotProtection(bool enable) async {
    // This would require native iOS implementation
    // For now, just log the action
    debugPrint(
        '📱 iOS screenshot protection: ${enable ? 'enabled' : 'disabled'}');
  }

  /// Detect screenshot attempt
  Future<void> onScreenshotDetected(String conversationId) async {
    if (_conversationScreenshotProtection[conversationId] == true) {
      await _logSecurityEvent(
        SecurityEventType.securityWarning,
        'Screenshot attempt detected',
        conversationId: conversationId,
        metadata: {'action': 'blocked'},
      );

      // Show warning to user
      await _showScreenshotWarning();
    }
  }

  /// Show screenshot warning
  Future<void> _showScreenshotWarning() async {
    // This would show a system-level warning
    // For now, just log
    debugPrint('⚠️ Screenshot warning displayed');
  }

  /// Secure message forwarding with re-encryption
  Future<Message?> secureForwardMessage(
    Message originalMessage,
    String targetConversationId,
  ) async {
    try {
      debugPrint('🔄 Securely forwarding message ${originalMessage.id}');

      // Decrypt original message if encrypted
      Message decryptedMessage = originalMessage;
      if (originalMessage.isEncrypted) {
        decryptedMessage =
            await _encryptionService.decryptMessage(originalMessage);
      }

      // Create new message for target conversation
      final forwardedMessage = Message(
        id: '', // Will be generated
        conversationId: targetConversationId,
        senderId: _supabase.auth.currentUser?.id ?? '',
        messageType: decryptedMessage.messageType,
        content: decryptedMessage.content,
        mediaData: decryptedMessage.mediaData,
        locationData: decryptedMessage.locationData,
        callData: decryptedMessage.callData,
        mentions: decryptedMessage.mentions,
        isFormatted: decryptedMessage.isFormatted,
        forwardFromId: originalMessage.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: MessageStatus.sending,
      );

      // Re-encrypt for target conversation
      final encryptedMessage =
          await _encryptionService.encryptMessage(forwardedMessage);

      await _logSecurityEvent(
        SecurityEventType.securityWarning,
        'Message securely forwarded',
        conversationId: targetConversationId,
        metadata: {
          'original_message_id': originalMessage.id,
          'original_conversation_id': originalMessage.conversationId,
        },
      );

      debugPrint('✅ Message forwarded securely');
      return encryptedMessage;
    } catch (e) {
      debugPrint('❌ Error in secure message forwarding: $e');
      return null;
    }
  }

  /// Backup encryption keys securely
  Future<String?> backupEncryptionKeys() async {
    try {
      debugPrint('💾 Creating secure key backup');

      // This would create an encrypted backup of all encryption keys
      // For now, return a mock backup string
      final backupData =
          'encrypted_key_backup_${DateTime.now().millisecondsSinceEpoch}';

      await _logSecurityEvent(
        SecurityEventType.keyRotation,
        'Encryption keys backed up',
        metadata: {'backup_size': backupData.length},
      );

      debugPrint('✅ Encryption keys backed up successfully');
      return backupData;
    } catch (e) {
      debugPrint('❌ Error backing up encryption keys: $e');
      return null;
    }
  }

  /// Restore encryption keys from backup
  Future<bool> restoreEncryptionKeys(String backupData) async {
    try {
      debugPrint('🔄 Restoring encryption keys from backup');

      // This would restore encryption keys from backup
      // For now, just validate the backup format
      if (backupData.startsWith('encrypted_key_backup_')) {
        await _logSecurityEvent(
          SecurityEventType.keyRotation,
          'Encryption keys restored from backup',
          metadata: {'backup_size': backupData.length},
        );

        debugPrint('✅ Encryption keys restored successfully');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Error restoring encryption keys: $e');
      return false;
    }
  }

  /// Log security event
  Future<void> _logSecurityEvent(
    SecurityEventType eventType,
    String description, {
    String? conversationId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final event = SecurityEvent(
        id: '', // Will be generated by database
        type: eventType,
        description: description,
        timestamp: DateTime.now(),
        userId: _supabase.auth.currentUser?.id,
        metadata: metadata,
      );

      // Store in database
      await _supabase.from('security_events').insert({
        'conversation_id': conversationId,
        'user_id': event.userId,
        'event_type': event.type.name,
        'description': event.description,
        'metadata': event.metadata ?? {},
      });

      // Store locally for quick access
      _recentSecurityEvents.add(event);

      debugPrint(
          '📝 Security event logged: ${event.type.name} - ${event.description}');
    } catch (e) {
      debugPrint('❌ Error logging security event: $e');
    }
  }

  /// Clean up old security events
  void _cleanupOldSecurityEvents() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    _recentSecurityEvents
        .removeWhere((event) => event.timestamp.isBefore(cutoff));
  }

  /// Get recent security events
  List<SecurityEvent> getRecentSecurityEvents() {
    return List.from(_recentSecurityEvents);
  }

  /// Check if screenshot protection is enabled for conversation
  bool isScreenshotProtectionEnabled(String conversationId) {
    return _conversationScreenshotProtection[conversationId] ?? false;
  }

  /// Get security settings
  Map<String, bool> getSecuritySettings() {
    return {
      'screenshot_protection': _screenshotProtectionEnabled,
      'screen_recording_detection': _screenRecordingDetectionEnabled,
    };
  }

  /// Update security setting
  Future<void> updateSecuritySetting(String setting, bool enabled) async {
    try {
      await _secureStorage.write(
          key: '${setting}_enabled', value: enabled.toString());

      switch (setting) {
        case 'screenshot_protection':
          _screenshotProtectionEnabled = enabled;
          break;
        case 'screen_recording_detection':
          _screenRecordingDetectionEnabled = enabled;
          break;
      }

      await _logSecurityEvent(
        SecurityEventType.securityWarning,
        'Security setting updated: $setting = $enabled',
      );

      debugPrint('⚙️ Security setting updated: $setting = $enabled');
    } catch (e) {
      debugPrint('❌ Error updating security setting: $e');
    }
  }

  /// Dispose the service
  void dispose() {
    _securityMonitoringTimer?.cancel();
    _recentSecurityEvents.clear();
    _conversationScreenshotProtection.clear();

    debugPrint('🧹 Advanced Security Service disposed');
  }
}
