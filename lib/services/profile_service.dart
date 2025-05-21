import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pulsemeet/models/profile.dart';

/// Service for managing user profiles
class ProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get the current user's profile
  Future<Profile?> getCurrentProfile() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        return null;
      }

      return getProfile(userId);
    } catch (e) {
      debugPrint('Error getting current profile: $e');
      return null;
    }
  }

  /// Get a user's profile by ID
  Future<Profile?> getProfile(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Profile.fromJson(response);
    } catch (e) {
      debugPrint('Error getting profile: $e');
      return null;
    }
  }

  /// Update a user's profile
  Future<Profile?> updateProfile(Profile profile) async {
    try {
      final response = await _supabase
          .from('profiles')
          .update(profile.toJson())
          .eq('id', profile.id)
          .select()
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Profile.fromJson(response);
    } catch (e) {
      debugPrint('Error updating profile: $e');
      return null;
    }
  }

  /// Get multiple profiles by IDs
  Future<List<Profile>> getProfiles(List<String> userIds) async {
    try {
      if (userIds.isEmpty) {
        return [];
      }

      final response = await _supabase
          .from('profiles')
          .select()
          .in_('id', userIds);

      return response
          .map<Profile>((json) => Profile.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error getting profiles: $e');
      return [];
    }
  }

  /// Search for profiles by username or display name
  Future<List<Profile>> searchProfiles(String query) async {
    try {
      if (query.isEmpty) {
        return [];
      }

      final response = await _supabase
          .from('profiles')
          .select()
          .or('username.ilike.%$query%,display_name.ilike.%$query%')
          .limit(20);

      return response
          .map<Profile>((json) => Profile.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error searching profiles: $e');
      return [];
    }
  }

  /// Get profiles of participants in a pulse
  Future<List<Profile>> getPulseParticipants(String pulseId) async {
    try {
      // Get participant user IDs
      final participantsResponse = await _supabase
          .from('pulse_participants')
          .select('user_id')
          .eq('pulse_id', pulseId)
          .eq('status', 'active');

      if (participantsResponse.isEmpty) {
        return [];
      }

      // Extract user IDs
      final userIds = participantsResponse
          .map<String>((item) => item['user_id'] as String)
          .toList();

      // Get profiles for these users
      return getProfiles(userIds);
    } catch (e) {
      debugPrint('Error getting pulse participants: $e');
      return [];
    }
  }
}
