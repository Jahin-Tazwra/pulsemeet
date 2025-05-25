import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/models/encryption_models.dart';

/// Service for managing disappearing messages functionality
class DisappearingMessagesService {
  static final DisappearingMessagesService _instance =
      DisappearingMessagesService._internal();
  factory DisappearingMessagesService() => _instance;
  DisappearingMessagesService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final Map<String, Timer> _messageTimers = {};
  final Map<String, DisappearingMessageSettings> _conversationSettings = {};

  /// Initialize the service
  Future<void> initialize() async {
    debugPrint('🕐 Initializing Disappearing Messages Service');

    // Load existing settings
    await _loadConversationSettings();

    // Schedule deletion for existing messages
    await _scheduleExistingMessages();

    debugPrint('✅ Disappearing Messages Service initialized');
  }

  /// Load disappearing message settings for all conversations
  Future<void> _loadConversationSettings() async {
    try {
      final response = await _supabase
          .from('conversations')
          .select(
              'id, disappearing_messages_enabled, disappearing_messages_duration')
          .eq('disappearing_messages_enabled', true);

      for (final row in response) {
        final conversationId = row['id'] as String;
        final duration =
            Duration(seconds: row['disappearing_messages_duration'] as int);

        _conversationSettings[conversationId] = DisappearingMessageSettings(
          enabled: true,
          duration: duration,
          enabledAt: DateTime.now(), // TODO: Get actual enabled time
        );
      }

      debugPrint(
          '📝 Loaded ${_conversationSettings.length} disappearing message settings');
    } catch (e) {
      debugPrint('❌ Error loading disappearing message settings: $e');
    }
  }

  /// Schedule deletion for existing messages
  Future<void> _scheduleExistingMessages() async {
    try {
      final conversationIds = _conversationSettings.keys.toList();
      if (conversationIds.isEmpty) return;

      final response = await _supabase
          .from('messages')
          .select('id, conversation_id, created_at')
          .in_('conversation_id', conversationIds)
          .eq('is_deleted', false);

      for (final row in response) {
        final messageId = row['id'] as String;
        final conversationId = row['conversation_id'] as String;
        final createdAt = DateTime.parse(row['created_at'] as String);

        final settings = _conversationSettings[conversationId];
        if (settings != null) {
          _scheduleMessageDeletion(
              messageId, conversationId, createdAt, settings.duration);
        }
      }

      debugPrint(
          '⏰ Scheduled deletion for ${response.length} existing messages');
    } catch (e) {
      debugPrint('❌ Error scheduling existing messages: $e');
    }
  }

  /// Enable disappearing messages for a conversation
  Future<void> enableDisappearingMessages(
    String conversationId,
    Duration duration,
  ) async {
    try {
      debugPrint(
          '🕐 Enabling disappearing messages for conversation $conversationId');

      // Update conversation settings
      await _supabase.from('conversations').update({
        'disappearing_messages_enabled': true,
        'disappearing_messages_duration': duration.inSeconds,
        'disappearing_messages_enabled_at': DateTime.now().toIso8601String(),
      }).eq('id', conversationId);

      // Store settings locally
      _conversationSettings[conversationId] = DisappearingMessageSettings(
        enabled: true,
        duration: duration,
        enabledAt: DateTime.now(),
      );

      // Schedule deletion for existing messages
      await _scheduleExistingMessagesForConversation(conversationId, duration);

      debugPrint(
          '✅ Disappearing messages enabled for conversation $conversationId');
    } catch (e) {
      debugPrint('❌ Error enabling disappearing messages: $e');
      rethrow;
    }
  }

  /// Disable disappearing messages for a conversation
  Future<void> disableDisappearingMessages(String conversationId) async {
    try {
      debugPrint(
          '🕐 Disabling disappearing messages for conversation $conversationId');

      // Update conversation settings
      await _supabase.from('conversations').update({
        'disappearing_messages_enabled': false,
        'disappearing_messages_duration': null,
        'disappearing_messages_enabled_at': null,
      }).eq('id', conversationId);

      // Remove local settings
      _conversationSettings.remove(conversationId);

      // Cancel existing timers for this conversation
      _cancelTimersForConversation(conversationId);

      debugPrint(
          '✅ Disappearing messages disabled for conversation $conversationId');
    } catch (e) {
      debugPrint('❌ Error disabling disappearing messages: $e');
      rethrow;
    }
  }

  /// Schedule message deletion when a new message is sent
  void scheduleNewMessage(Message message) {
    final settings = _conversationSettings[message.conversationId];
    if (settings != null && settings.enabled) {
      _scheduleMessageDeletion(
        message.id,
        message.conversationId,
        message.createdAt,
        settings.duration,
      );
    }
  }

  /// Schedule deletion for existing messages in a conversation
  Future<void> _scheduleExistingMessagesForConversation(
    String conversationId,
    Duration duration,
  ) async {
    try {
      final response = await _supabase
          .from('messages')
          .select('id, created_at')
          .eq('conversation_id', conversationId)
          .eq('is_deleted', false);

      for (final row in response) {
        final messageId = row['id'] as String;
        final createdAt = DateTime.parse(row['created_at'] as String);

        _scheduleMessageDeletion(
            messageId, conversationId, createdAt, duration);
      }
    } catch (e) {
      debugPrint('❌ Error scheduling existing messages for conversation: $e');
    }
  }

  /// Schedule deletion for a specific message
  void _scheduleMessageDeletion(
    String messageId,
    String conversationId,
    DateTime createdAt,
    Duration duration,
  ) {
    final deleteAt = createdAt.add(duration);
    final now = DateTime.now();

    // If message should already be deleted, delete it immediately
    if (deleteAt.isBefore(now)) {
      _deleteMessage(messageId);
      return;
    }

    // Calculate remaining time
    final remainingTime = deleteAt.difference(now);

    // Cancel existing timer if any
    _messageTimers[messageId]?.cancel();

    // Schedule deletion
    _messageTimers[messageId] = Timer(remainingTime, () {
      _deleteMessage(messageId);
      _messageTimers.remove(messageId);
    });

    debugPrint(
        '⏰ Scheduled deletion for message $messageId in ${remainingTime.inSeconds}s');
  }

  /// Delete a message
  Future<void> _deleteMessage(String messageId) async {
    try {
      debugPrint('🗑️ Deleting disappearing message $messageId');

      await _supabase.from('messages').update({
        'is_deleted': true,
        'deleted_at': DateTime.now().toIso8601String(),
        'content': '', // Clear content
        'media_data': null, // Clear media data
        'location_data': null, // Clear location data
      }).eq('id', messageId);

      debugPrint('✅ Message $messageId deleted successfully');
    } catch (e) {
      debugPrint('❌ Error deleting message $messageId: $e');
    }
  }

  /// Cancel all timers for a conversation
  void _cancelTimersForConversation(String conversationId) {
    final timersToCancel = <String>[];

    for (final entry in _messageTimers.entries) {
      // Note: We'd need to track conversation IDs for messages to do this properly
      // For now, we'll just cancel all timers when disabling
      timersToCancel.add(entry.key);
    }

    for (final messageId in timersToCancel) {
      _messageTimers[messageId]?.cancel();
      _messageTimers.remove(messageId);
    }
  }

  /// Get disappearing message settings for a conversation
  DisappearingMessageSettings? getSettings(String conversationId) {
    return _conversationSettings[conversationId];
  }

  /// Check if disappearing messages are enabled for a conversation
  bool isEnabled(String conversationId) {
    return _conversationSettings[conversationId]?.enabled ?? false;
  }

  /// Get time remaining for a message
  Duration? getTimeRemaining(String messageId, DateTime createdAt) {
    final timer = _messageTimers[messageId];
    if (timer == null) return null;

    // Calculate remaining time based on timer
    // This is approximate since we don't store the exact deletion time
    return const Duration(seconds: 0); // TODO: Implement proper time tracking
  }

  /// Get all active timers count (for debugging)
  int get activeTimersCount => _messageTimers.length;

  /// Dispose the service
  void dispose() {
    // Cancel all timers
    for (final timer in _messageTimers.values) {
      timer.cancel();
    }
    _messageTimers.clear();
    _conversationSettings.clear();

    debugPrint('🧹 Disappearing Messages Service disposed');
  }
}
