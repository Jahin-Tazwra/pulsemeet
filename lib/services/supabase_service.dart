import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/pulse.dart';
import '../models/profile.dart';
import '../models/chat_message.dart';

/// Service class for interacting with Supabase
class SupabaseService {
  final SupabaseClient _client = SupabaseConfig.client;

  // Expose client for direct access in special cases
  SupabaseClient get client => _client;

  /// Get the current user's ID
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Check if a user is authenticated
  bool get isAuthenticated => _client.auth.currentUser != null;

  /// Stream of authentication state changes
  Stream<bool> get authStateChanges {
    // Start with the current auth state
    final initialState = _client.auth.currentSession != null;
    debugPrint('Initial auth state: $initialState');

    // Create a StreamController to manage the stream
    final controller = StreamController<bool>.broadcast();

    // Add the initial state
    controller.add(initialState);

    // Listen to auth state changes
    _client.auth.onAuthStateChange.listen((event) {
      final isAuthenticated = event.session != null;
      debugPrint(
          'Auth state changed: ${event.event}, isAuthenticated: $isAuthenticated');
      controller.add(isAuthenticated);
    });

    return controller.stream;
  }

  /// Sign in with phone number
  Future<void> signInWithPhone(String phoneNumber) async {
    await _client.auth.signInWithOtp(phone: phoneNumber);
  }

  /// Verify phone OTP
  Future<AuthResponse> verifyPhoneOTP(String phoneNumber, String otp) async {
    final response = await _client.auth.verifyOTP(
      phone: phoneNumber,
      token: otp,
      type: OtpType.sms,
    );
    return response;
  }

  /// Sign in with Google
  Future<void> signInWithGoogle() async {
    try {
      debugPrint('Starting Google sign-in process');
      if (kIsWeb) {
        // web uses the hosted flow redirect
        await _client.auth.signInWithOAuth(
          Provider.google, // Using the Provider enum from Supabase
        );
      } else {
        // mobile uses your Android intent‐filter deep link
        final response = await _client.auth.signInWithOAuth(
          Provider.google, // Using the Provider enum from Supabase
          redirectTo: 'com.example.pulsemeet://login-callback',
        );
        debugPrint('Google sign-in response: $response');
      }
      debugPrint('Google sign-in process completed');

      // Force refresh the auth state
      final session = await _client.auth.refreshSession();
      debugPrint('Session after refresh: ${session.session}');
    } catch (e) {
      debugPrint('Error during Google sign-in: $e');
      rethrow;
    }
  }

  /// Sign in with Apple (disabled due to compatibility issues)
  Future<void> signInWithApple() async {
    throw UnimplementedError(
        'Apple Sign-In is disabled due to compatibility issues with Android. '
        'Please use another sign-in method.');
  }

  /// Sign out
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Create or update user profile
  Future<Profile> upsertProfile({
    required String id,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? phoneNumber,
    String? bio,
  }) async {
    final now = DateTime.now();

    // Prepare data for upsert
    final data = {
      'id': id,
      if (username != null) 'username': username,
      if (displayName != null) 'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (bio != null) 'bio': bio,
      'updated_at': now.toIso8601String(),
      // For new profiles, set created_at and last_seen_at
      'created_at': now.toIso8601String(),
      'last_seen_at': now.toIso8601String(),
      // Default values for verification
      'is_verified': false,
      'verification_status': 'unverified',
    };

    try {
      final response =
          await _client.from('profiles').upsert(data).select().single();
      return Profile.fromJson(response);
    } catch (e) {
      debugPrint('Error upserting profile: $e');

      // If there's an error, try to create a minimal profile
      final minimalData = {
        'id': id,
        'username': username ?? 'user_$id'.substring(0, 10),
        'display_name': displayName ?? 'New User',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'last_seen_at': now.toIso8601String(),
        'is_verified': false,
        'verification_status': 'unverified',
      };

      final response =
          await _client.from('profiles').upsert(minimalData).select().single();
      return Profile.fromJson(response);
    }
  }

  /// Get user profile by ID
  /// If the profile doesn't exist, it will create a new one with default values
  Future<Profile> getProfile(String userId) async {
    try {
      // Try to get the existing profile
      final response =
          await _client.from('profiles').select().eq('id', userId).single();
      return Profile.fromJson(response);
    } catch (e) {
      debugPrint('Profile not found, creating a new one: $e');

      // If profile doesn't exist, create a new one with default values
      final user = _client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Extract user information from auth metadata if available
      final userMetadata = user.userMetadata;
      final String? name = userMetadata?['full_name'] ?? userMetadata?['name'];
      final String? email = user.email;
      final String? avatarUrl =
          userMetadata?['avatar_url'] ?? userMetadata?['picture'];

      // Generate a username from email or a random string
      String? username;
      if (email != null) {
        username = email.split('@').first;
      }

      // Create a new profile
      return await upsertProfile(
        id: userId,
        username: username,
        displayName: name,
        avatarUrl: avatarUrl,
      );
    }
  }

  /// Upload avatar image
  Future<String> uploadAvatar(String userId, File imageFile) async {
    final fileExt = imageFile.path.split('.').last;
    final fileName = '$userId/avatar.$fileExt';
    final filePath = await _client.storage.from('avatars').upload(
          fileName,
          imageFile,
          fileOptions: const FileOptions(upsert: true),
        );

    final imageUrl = _client.storage.from('avatars').getPublicUrl(filePath);

    // Update profile with new avatar URL
    await upsertProfile(id: userId, avatarUrl: imageUrl);

    return imageUrl;
  }

  /// Create a new pulse (meetup)
  Future<Pulse> createPulse({
    required String title,
    required String description,
    String? activityEmoji,
    required double latitude,
    required double longitude,
    required int radius,
    required DateTime startTime,
    required DateTime endTime,
    int? maxParticipants,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final data = {
      'creator_id': userId,
      'title': title,
      'description': description,
      'activity_emoji': activityEmoji,
      'location': 'POINT($longitude $latitude)',
      'radius': radius,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      if (maxParticipants != null) 'max_participants': maxParticipants,
    };

    // Insert the pulse and return with extracted coordinates
    final response = await _client.from('pulses').insert(data).select('''
      *,
      st_x(location::geometry) as longitude,
      st_y(location::geometry) as latitude
    ''').single();

    // Verify the coordinates were stored correctly
    if (response['longitude'] != null && response['latitude'] != null) {
      final storedLng = double.parse(response['longitude'].toString());
      final storedLat = double.parse(response['latitude'].toString());

      debugPrint('Stored pulse coordinates: lat=$storedLat, lng=$storedLng');

      // Check if the coordinates match what we sent
      if ((storedLat - latitude).abs() > 0.0001 ||
          (storedLng - longitude).abs() > 0.0001) {
        debugPrint(
            'WARNING: Stored coordinates differ from input coordinates!');
      }
    } else {
      debugPrint('WARNING: No coordinates extracted from stored pulse');
    }

    // Automatically join the pulse as creator
    await joinPulse(response['id']);

    return Pulse.fromJson(response);
  }

  /// Get nearby pulses
  Future<List<Pulse>> getNearbyPulses(
    double latitude,
    double longitude, {
    int maxDistance = 5000,
  }) async {
    try {
      debugPrint(
          'Fetching nearby pulses at ($latitude, $longitude) with max distance $maxDistance meters');

      // Use the RPC function that already extracts coordinates
      final response = await _client.rpc(
        'find_nearby_pulses_with_coords',
        params: {
          'user_lat': latitude,
          'user_lng': longitude,
          'max_distance_meters': maxDistance,
        },
      );

      debugPrint(
          'Received response: ${response.runtimeType}, length: ${response is List ? response.length : 0}');

      // Ensure response is a List and convert each item to a Pulse
      if (response is List) {
        final pulses = response
            .map((item) {
              if (item is Map<String, dynamic>) {
                try {
                  // Debug the location data
                  debugPrint(
                      'Pulse ${item['id']} location data: ${item['location']}');
                  debugPrint(
                      'Pulse ${item['id']} coordinates: lat=${item['latitude']}, lng=${item['longitude']}');

                  return Pulse.fromJson(item);
                } catch (e) {
                  debugPrint('Error parsing pulse: $e');
                  debugPrint('Problematic data: $item');
                  return null;
                }
              } else {
                debugPrint('Invalid pulse data format: $item');
                return null;
              }
            })
            .where((pulse) => pulse != null)
            .cast<Pulse>()
            .toList();

        debugPrint('Successfully parsed ${pulses.length} pulses');
        return pulses;
      } else {
        debugPrint('Invalid response format: $response');
        return [];
      }
    } catch (e) {
      debugPrint('Error fetching nearby pulses: $e');

      // If there's an error with the RPC function, try the fallback approach
      try {
        debugPrint('Falling back to direct query for nearby pulses');

        // Get pulses with extracted coordinates
        final response = await _client.rpc(
          'get_pulses_with_coordinates',
          params: {},
        );

        if (response is List) {
          // Filter pulses by distance manually
          final userPoint = LatLng(latitude, longitude);
          final nearbyPulses = <Pulse>[];

          for (final item in response) {
            try {
              if (item is Map<String, dynamic>) {
                final pulse = Pulse.fromJson(item);

                // Calculate distance using the Haversine formula
                final distance = _calculateDistance(userPoint, pulse.location);

                // Convert to meters
                final distanceMeters = distance * 1000;

                // Only include pulses within the max distance
                if (distanceMeters <= maxDistance) {
                  // Add distance to the pulse data
                  pulse.distanceMeters = distanceMeters;
                  nearbyPulses.add(pulse);
                  debugPrint(
                      'Added nearby pulse: ${pulse.title} at distance ${pulse.formattedDistance}');
                }
              }
            } catch (e) {
              debugPrint('Error processing pulse: $e');
            }
          }

          // Sort by distance
          nearbyPulses.sort((a, b) {
            final distA = a.distanceMeters ?? double.infinity;
            final distB = b.distanceMeters ?? double.infinity;
            return distA.compareTo(distB);
          });

          return nearbyPulses;
        }
      } catch (fallbackError) {
        debugPrint('Error in fallback approach: $fallbackError');
      }

      return [];
    }
  }

  // Calculate distance between two points using the Haversine formula
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371.0; // Earth's radius in kilometers

    // Convert latitude and longitude from degrees to radians
    final double lat1 = _degreesToRadians(point1.latitude);
    final double lon1 = _degreesToRadians(point1.longitude);
    final double lat2 = _degreesToRadians(point2.latitude);
    final double lon2 = _degreesToRadians(point2.longitude);

    // Haversine formula
    final double dLat = lat2 - lat1;
    final double dLon = lon2 - lon1;
    final double a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final double distance = earthRadius * c;

    return distance;
  }

  // Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }

  /// Join a pulse
  Future<void> joinPulse(String pulseId) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    await _client.from('pulse_participants').upsert({
      'pulse_id': pulseId,
      'user_id': userId,
      'status': 'active',
      'joined_at': DateTime.now().toIso8601String(),
      'left_at': null,
    });
  }

  /// Leave a pulse
  Future<void> leavePulse(String pulseId) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    await _client
        .from('pulse_participants')
        .update({'status': 'left', 'left_at': DateTime.now().toIso8601String()})
        .eq('pulse_id', pulseId)
        .eq('user_id', userId);
  }

  /// Send a chat message
  Future<ChatMessage> sendChatMessage({
    required String pulseId,
    required String content,
    String messageType = 'text',
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final data = {
      'pulse_id': pulseId,
      'sender_id': userId,
      'content': content,
      'message_type': messageType,
    };

    final response =
        await _client.from('chat_messages').insert(data).select().single();

    return ChatMessage.fromJson(response);
  }

  /// Subscribe to chat messages for a pulse
  Stream<List<ChatMessage>> subscribeToChatMessages(String pulseId) {
    final stream = _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('pulse_id', pulseId)
        .order('created_at')
        .map(
          (data) =>
              data.map((message) => ChatMessage.fromJson(message)).toList(),
        );

    return stream;
  }

  /// Report a user
  Future<void> reportUser({
    required String reportedUserId,
    required String reportType,
    String? pulseId,
    String? description,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final data = {
      'reporter_id': userId,
      'reported_user_id': reportedUserId,
      'report_type': reportType,
      if (pulseId != null) 'pulse_id': pulseId,
      if (description != null) 'description': description,
    };

    await _client.from('user_reports').insert(data);
  }

  /// Block a user
  Future<void> blockUser(String blockedUserId) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    await _client.from('user_blocks').upsert({
      'blocker_id': userId,
      'blocked_id': blockedUserId,
    });
  }

  /// Unblock a user
  Future<void> unblockUser(String blockedUserId) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    await _client
        .from('user_blocks')
        .delete()
        .eq('blocker_id', userId)
        .eq('blocked_id', blockedUserId);
  }

  /// Get pulses created by the current user
  Future<List<Pulse>> getCreatedPulses() async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    try {
      // We need to use a raw query to extract coordinates
      final response = await _client.rpc(
        'get_pulses_with_coordinates',
        params: {
          'creator_id_param': userId,
        },
      );

      if (response is List) {
        final pulses = response
            .map((item) {
              if (item is Map<String, dynamic>) {
                try {
                  return Pulse.fromJson(item);
                } catch (e) {
                  debugPrint('Error parsing pulse: $e');
                  return null;
                }
              } else {
                return null;
              }
            })
            .where((pulse) => pulse != null)
            .cast<Pulse>()
            .toList();

        return pulses;
      } else {
        return [];
      }
    } catch (e) {
      debugPrint('Error fetching created pulses: $e');
      rethrow;
    }
  }

  /// Get a pulse by ID
  Future<Pulse?> getPulseById(String pulseId) async {
    try {
      debugPrint('Fetching pulse with ID: $pulseId');

      // Get the pulse details with extracted coordinates
      final response = await _client.rpc(
        'get_pulse_with_coordinates',
        params: {
          'pulse_id_param': pulseId,
        },
      ).single();

      if (response != null) {
        // Add creator_name from the joined profiles table
        if (response['profiles'] != null &&
            response['profiles']['display_name'] != null) {
          response['creator_name'] = response['profiles']['display_name'];
        }

        // Parse the pulse
        final pulse = Pulse.fromJson(response);
        return pulse;
      }

      return null;
    } catch (e) {
      debugPrint('Error fetching pulse by ID: $e');
      return null;
    }
  }

  /// Get pulses joined by the current user
  Future<List<Pulse>> getJoinedPulses() async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Get pulse IDs that the user has joined
      final participantResponse = await _client
          .from('pulse_participants')
          .select('pulse_id')
          .eq('user_id', userId)
          .eq('status', 'active');

      if (participantResponse is! List || participantResponse.isEmpty) {
        return [];
      }

      // Extract pulse IDs
      final pulseIds = participantResponse
          .map((item) => item['pulse_id'] as String)
          .toList();

      // Get pulse details with extracted coordinates
      final pulsesResponse = await _client.rpc(
        'get_joined_pulses_with_coordinates',
        params: {
          'pulse_ids': pulseIds,
        },
      );

      if (pulsesResponse is List) {
        final pulses = pulsesResponse
            .map((item) {
              if (item is Map<String, dynamic>) {
                try {
                  return Pulse.fromJson(item);
                } catch (e) {
                  debugPrint('Error parsing pulse: $e');
                  return null;
                }
              } else {
                return null;
              }
            })
            .where((pulse) => pulse != null)
            .cast<Pulse>()
            .toList();

        return pulses;
      } else {
        return [];
      }
    } catch (e) {
      debugPrint('Error fetching joined pulses: $e');
      rethrow;
    }
  }
}
