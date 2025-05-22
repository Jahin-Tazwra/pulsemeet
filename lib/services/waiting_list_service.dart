import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pulsemeet/models/waiting_list_entry.dart';
import 'package:pulsemeet/models/profile.dart';

/// Service to manage pulse waiting lists
class WaitingListService {
  // Singleton instance
  static final WaitingListService _instance = WaitingListService._internal();
  factory WaitingListService() => _instance;
  WaitingListService._internal();

  // Supabase client
  final _supabase = Supabase.instance.client;

  // Stream controllers
  final _waitingListController =
      StreamController<List<WaitingListEntry>>.broadcast();
  final _userPositionController = StreamController<int>.broadcast();

  // Cache of waiting list entries by pulse ID
  final Map<String, List<WaitingListEntry>> _waitingListCache = {};

  // Cache of user positions by pulse ID
  final Map<String, int> _userPositionCache = {};

  // Getters for streams
  Stream<List<WaitingListEntry>> get waitingListStream =>
      _waitingListController.stream;
  Stream<int> get userPositionStream => _userPositionController.stream;

  /// Get waiting list for a pulse
  Future<List<WaitingListEntry>> getWaitingList(String pulseId) async {
    try {
      // Check cache first
      if (_waitingListCache.containsKey(pulseId)) {
        return _waitingListCache[pulseId]!;
      }

      // Get waiting list from database
      final response = await _supabase
          .from('pulse_waiting_list')
          .select('*, profiles:user_id(id, username, display_name, avatar_url)')
          .eq('pulse_id', pulseId)
          .eq('status', 'Waiting')
          .order('position', ascending: true);

      // Parse response
      final List<WaitingListEntry> waitingList = [];
      for (final item in response) {
        try {
          final entry = WaitingListEntry.fromJson(item);

          // Add profile information if available
          if (item['profiles'] != null) {
            try {
              // Make sure required fields are present
              final profileData = Map<String, dynamic>.from(item['profiles']);

              // Add default timestamps if missing
              if (profileData['created_at'] == null) {
                profileData['created_at'] = DateTime.now().toIso8601String();
              }
              if (profileData['updated_at'] == null) {
                profileData['updated_at'] = DateTime.now().toIso8601String();
              }
              if (profileData['last_seen_at'] == null) {
                profileData['last_seen_at'] = DateTime.now().toIso8601String();
              }

              final profile = Profile.fromJson(profileData);
              waitingList.add(entry.copyWith(
                username: profile.username,
                displayName: profile.displayName,
                avatarUrl: profile.avatarUrl,
              ));
            } catch (profileError) {
              debugPrint(
                  'Error parsing profile in waiting list: $profileError');
              waitingList.add(entry);
            }
          } else {
            waitingList.add(entry);
          }
        } catch (entryError) {
          debugPrint('Error parsing waiting list entry: $entryError');
          // Continue to next entry
        }
      }

      // Update cache
      _waitingListCache[pulseId] = waitingList;

      // Notify listeners
      _waitingListController.add(waitingList);

      return waitingList;
    } catch (e) {
      debugPrint('Error getting waiting list: $e');
      return [];
    }
  }

  /// Get user's position in waiting list
  Future<int> getUserPosition(String pulseId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return 0;

      // Check cache first
      if (_userPositionCache.containsKey(pulseId)) {
        return _userPositionCache[pulseId]!;
      }

      // Get user's position from database
      final response = await _supabase
          .from('pulse_waiting_list')
          .select('position')
          .eq('pulse_id', pulseId)
          .eq('user_id', userId)
          .eq('status', 'Waiting');

      // Handle case where user is not on waiting list (empty result)
      if (response.isEmpty) {
        // Update cache with 0 position
        _userPositionCache[pulseId] = 0;
        _userPositionController.add(0);
        return 0;
      }

      final position = response.first['position'] as int? ?? 0;

      // Update cache
      _userPositionCache[pulseId] = position;

      // Notify listeners
      _userPositionController.add(position);

      return position;
    } catch (e) {
      debugPrint('Error getting user position: $e');
      return 0;
    }
  }

  /// Check if user is on waiting list
  Future<bool> isUserOnWaitingList(String pulseId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final position = await getUserPosition(pulseId);
      return position > 0;
    } catch (e) {
      debugPrint('Error checking if user is on waiting list: $e');
      return false;
    }
  }

  /// Join waiting list
  Future<bool> joinWaitingList(String pulseId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Check if user is already on waiting list
      final isOnWaitingList = await isUserOnWaitingList(pulseId);
      if (isOnWaitingList) {
        return true; // Already on waiting list
      }

      // Get next position
      final nextPosition = await _supabase.rpc(
        'get_next_waiting_list_position',
        params: {
          'pulse_id_param': pulseId,
        },
      );

      // Add to waiting list
      await _supabase.from('pulse_waiting_list').insert({
        'pulse_id': pulseId,
        'user_id': userId,
        'position': nextPosition,
        'status': 'Waiting',
        'joined_at': DateTime.now().toIso8601String(),
      });

      // Refresh waiting list
      await getWaitingList(pulseId);
      await getUserPosition(pulseId);

      return true;
    } catch (e) {
      debugPrint('Error joining waiting list: $e');
      return false;
    }
  }

  /// Leave waiting list
  Future<bool> leaveWaitingList(String pulseId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Delete from waiting list
      await _supabase
          .from('pulse_waiting_list')
          .delete()
          .eq('pulse_id', pulseId)
          .eq('user_id', userId);

      // Update cache
      _userPositionCache.remove(pulseId);
      _userPositionController.add(0);

      // Refresh waiting list
      await getWaitingList(pulseId);

      return true;
    } catch (e) {
      debugPrint('Error leaving waiting list: $e');
      return false;
    }
  }

  /// Subscribe to waiting list changes
  Future<void> subscribeToWaitingList(String pulseId) async {
    // Get initial waiting list
    await getWaitingList(pulseId);
    await getUserPosition(pulseId);

    // Subscribe to changes
    _supabase.channel('public:pulse_waiting_list').on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(
        event: '*',
        schema: 'public',
        table: 'pulse_waiting_list',
        filter: 'pulse_id=eq.$pulseId',
      ),
      (payload, [ref]) async {
        // Refresh waiting list
        await getWaitingList(pulseId);
        await getUserPosition(pulseId);

        // Check if user was promoted
        if (payload['new'] != null &&
            payload['new']['status'] == 'Promoted' &&
            payload['new']['user_id'] == _supabase.auth.currentUser?.id) {
          // Show a simple notification
          debugPrint(
              'User promoted from waiting list to participant for pulse: $pulseId');
        }
      },
    ).subscribe();
  }

  /// Get waiting list count
  Future<int> getWaitingListCount(String pulseId) async {
    try {
      final response = await _supabase
          .from('pulse_waiting_list')
          .select('id')
          .eq('pulse_id', pulseId)
          .eq('status', 'Waiting');

      return response.length;
    } catch (e) {
      debugPrint('Error getting waiting list count: $e');
      return 0;
    }
  }

  /// Dispose resources
  void dispose() {
    _waitingListController.close();
    _userPositionController.close();
  }
}
