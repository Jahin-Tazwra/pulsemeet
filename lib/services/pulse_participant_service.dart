import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to manage pulse participants
class PulseParticipantService {
  // Singleton instance
  static final PulseParticipantService _instance = PulseParticipantService._internal();
  factory PulseParticipantService() => _instance;
  PulseParticipantService._internal();

  // Supabase client
  final _supabase = Supabase.instance.client;

  // Stream controllers
  final _participantsController = StreamController<List<Profile>>.broadcast();
  final _typingUsersController = StreamController<Map<String, DateTime>>.broadcast();

  // Cache of participants by pulse ID
  final Map<String, List<Profile>> _participantsCache = {};
  
  // Cache of typing users by pulse ID
  final Map<String, Map<String, DateTime>> _typingUsersCache = {};

  // Stream of participants
  Stream<List<Profile>> get participantsStream => _participantsController.stream;
  
  // Stream of typing users
  Stream<Map<String, DateTime>> get typingUsersStream => _typingUsersController.stream;

  /// Get participants for a pulse
  Future<List<Profile>> getParticipants(String pulseId) async {
    try {
      // Check cache first
      if (_participantsCache.containsKey(pulseId)) {
        return _participantsCache[pulseId]!;
      }

      // Get participants from database
      final response = await _supabase
          .from('pulse_participants')
          .select('user_id, profiles:user_id(id, username, display_name, avatar_url)')
          .eq('pulse_id', pulseId)
          .eq('status', 'active');

      // Parse response
      final List<Profile> participants = [];
      for (final item in response) {
        if (item['profiles'] != null) {
          participants.add(Profile.fromJson(item['profiles']));
        }
      }

      // Update cache
      _participantsCache[pulseId] = participants;
      
      // Notify listeners
      _participantsController.add(participants);

      return participants;
    } catch (e) {
      debugPrint('Error getting participants: $e');
      return [];
    }
  }

  /// Subscribe to participants for a pulse
  Future<void> subscribeToParticipants(String pulseId) async {
    // Get initial participants
    await getParticipants(pulseId);

    // Subscribe to changes
    _supabase
        .channel('public:pulse_participants')
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
            event: '*',
            schema: 'public',
            table: 'pulse_participants',
            filter: 'pulse_id=eq.$pulseId',
          ),
          (payload, [ref]) async {
            // Refresh participants
            await getParticipants(pulseId);
          },
        )
        .subscribe();
  }

  /// Set user typing status
  Future<void> setTypingStatus(String pulseId, String userId, bool isTyping) async {
    try {
      // Initialize typing users cache for this pulse if needed
      if (!_typingUsersCache.containsKey(pulseId)) {
        _typingUsersCache[pulseId] = {};
      }

      // Update typing status
      if (isTyping) {
        // Add user to typing users with current timestamp
        _typingUsersCache[pulseId]![userId] = DateTime.now();
      } else {
        // Remove user from typing users
        _typingUsersCache[pulseId]!.remove(userId);
      }

      // Notify listeners
      _typingUsersController.add(_typingUsersCache[pulseId]!);

      // Update typing status in database
      await _supabase.from('pulse_typing_status').upsert({
        'pulse_id': pulseId,
        'user_id': userId,
        'is_typing': isTyping,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error setting typing status: $e');
    }
  }

  /// Subscribe to typing status for a pulse
  Future<void> subscribeToTypingStatus(String pulseId) async {
    // Initialize typing users cache for this pulse
    _typingUsersCache[pulseId] = {};

    // Get current typing users
    try {
      final response = await _supabase
          .from('pulse_typing_status')
          .select()
          .eq('pulse_id', pulseId)
          .eq('is_typing', true);

      // Parse response
      for (final item in response) {
        final userId = item['user_id'];
        final updatedAt = DateTime.parse(item['updated_at']);
        
        // Only consider users who have been typing in the last 10 seconds
        if (DateTime.now().difference(updatedAt).inSeconds < 10) {
          _typingUsersCache[pulseId]![userId] = updatedAt;
        }
      }

      // Notify listeners
      _typingUsersController.add(_typingUsersCache[pulseId]!);
    } catch (e) {
      debugPrint('Error getting typing status: $e');
    }

    // Subscribe to changes
    _supabase
        .channel('public:pulse_typing_status')
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
            event: '*',
            schema: 'public',
            table: 'pulse_typing_status',
            filter: 'pulse_id=eq.$pulseId',
          ),
          (payload, [ref]) {
            // Update typing status
            if (payload['new'] != null) {
              final userId = payload['new']['user_id'];
              final isTyping = payload['new']['is_typing'];
              final updatedAt = DateTime.parse(payload['new']['updated_at']);

              if (isTyping) {
                _typingUsersCache[pulseId]![userId] = updatedAt;
              } else {
                _typingUsersCache[pulseId]!.remove(userId);
              }

              // Notify listeners
              _typingUsersController.add(_typingUsersCache[pulseId]!);
            }
          },
        )
        .subscribe();

    // Start a timer to clean up old typing statuses
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_typingUsersCache.containsKey(pulseId)) {
        bool hasChanges = false;
        
        // Remove users who haven't typed in the last 10 seconds
        _typingUsersCache[pulseId]!.removeWhere((userId, timestamp) {
          final isExpired = DateTime.now().difference(timestamp).inSeconds > 10;
          if (isExpired) hasChanges = true;
          return isExpired;
        });

        // Notify listeners if there were changes
        if (hasChanges) {
          _typingUsersController.add(_typingUsersCache[pulseId]!);
        }
      }
    });
  }

  /// Dispose resources
  void dispose() {
    _participantsController.close();
    _typingUsersController.close();
  }
}
