import 'dart:async';
import 'dart:convert';
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
    final currentUser = _client.auth.currentUser;
    debugPrint(
        'Initial auth state: $initialState, User: ${currentUser?.id ?? 'none'}');

    if (currentUser != null) {
      debugPrint(
          'User details: Email: ${currentUser.email}, Phone: ${currentUser.phone}');
      debugPrint('User metadata: ${currentUser.userMetadata}');
    }

    // Create a StreamController to manage the stream
    final controller = StreamController<bool>.broadcast();

    // Add the initial state
    controller.add(initialState);

    // Listen to auth state changes
    _client.auth.onAuthStateChange.listen((event) {
      final isAuthenticated = event.session != null;
      final user = event.session?.user;

      debugPrint(
          'Auth state changed: ${event.event}, isAuthenticated: $isAuthenticated');

      if (isAuthenticated && user != null) {
        debugPrint('Authenticated user: ${user.id}');
        debugPrint('User details: Email: ${user.email}, Phone: ${user.phone}');
        debugPrint('User metadata: ${user.userMetadata}');

        // Check if profile exists and create if needed
        _ensureUserProfile(user);
      }

      controller.add(isAuthenticated);
    });

    return controller.stream;
  }

  /// Ensure the user has a profile
  Future<void> _ensureUserProfile(User user) async {
    try {
      // Check if profile exists
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        debugPrint('Creating profile for user ${user.id}');

        // Extract name and avatar from user metadata
        final metadata = user.userMetadata;
        final name = metadata?['name'] as String? ??
            metadata?['full_name'] as String? ??
            'User';
        final avatarUrl = metadata?['avatar_url'] as String? ??
            metadata?['picture'] as String?;

        // Create profile
        await _client.from('profiles').insert({
          'id': user.id,
          'username': name,
          'avatar_url': avatarUrl,
          'updated_at': DateTime.now().toIso8601String(),
        });

        debugPrint('Profile created successfully');
      } else {
        debugPrint('User profile already exists');
      }
    } catch (e) {
      debugPrint('Error ensuring user profile: $e');
    }
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

      // Check if there's an existing session first
      final currentSession = _client.auth.currentSession;
      if (currentSession != null) {
        debugPrint('User already has a valid session');
        return;
      }

      if (kIsWeb) {
        // web uses the hosted flow redirect
        await _client.auth.signInWithOAuth(
          Provider.google,
        );
      } else {
        // mobile uses your Android/iOS intent‐filter deep link
        await _client.auth.signInWithOAuth(
          Provider.google,
          redirectTo: 'com.example.pulsemeet://login-callback',
        );
        debugPrint('Google sign-in initiated');
      }

      // Note: The actual sign-in happens asynchronously through the redirect flow
      // The app will be redirected to Google and then back to the app via the deep link
      // The auth state listener in the app will handle the sign-in completion
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
    String? email,
    NotificationSettings? notificationSettings,
    PrivacySettings? privacySettings,
    ThemeMode? themeMode,
    String? location,
    List<String>? interests,
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
      if (email != null) 'email': email,
      if (notificationSettings != null)
        'notification_settings': jsonEncode(notificationSettings.toJson()),
      if (privacySettings != null)
        'privacy_settings': jsonEncode(privacySettings.toJson()),
      if (themeMode != null) 'theme_mode': _themeModeTString(themeMode),
      if (location != null) 'location': location,
      if (interests != null) 'interests': jsonEncode(interests),
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

  /// Convert theme mode to string
  String _themeModeTString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
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

  /// Upload avatar image with error handling
  Future<String> uploadAvatar(String userId, File imageFile) async {
    try {
      // Validate file size (max 5MB)
      final fileSize = await imageFile.length();
      if (fileSize > 5 * 1024 * 1024) {
        throw Exception('Image file is too large. Maximum size is 5MB.');
      }

      // Validate file extension
      final fileExt = imageFile.path.split('.').last.toLowerCase();
      final validExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
      if (!validExtensions.contains(fileExt)) {
        throw Exception(
            'Invalid file format. Supported formats: ${validExtensions.join(', ')}');
      }

      // Create a unique filename with timestamp to avoid caching issues
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '$userId/avatar_$timestamp.$fileExt';

      // Upload the file
      final filePath = await _client.storage.from('avatars').upload(
            fileName,
            imageFile,
            fileOptions: const FileOptions(upsert: true),
          );

      // Get the public URL
      final imageUrl = _client.storage.from('avatars').getPublicUrl(filePath);

      // Update profile with new avatar URL
      await upsertProfile(id: userId, avatarUrl: imageUrl);

      return imageUrl;
    } catch (e) {
      debugPrint('Error uploading avatar: $e');

      // Check for specific error types
      if (e.toString().contains('permission')) {
        throw Exception(
            'Permission denied when uploading avatar. Please try again later.');
      } else if (e.toString().contains('network')) {
        throw Exception(
            'Network error when uploading avatar. Please check your connection and try again.');
      } else if (e.toString().contains('storage')) {
        throw Exception(
            'Storage error when uploading avatar. Please try again later.');
      }

      // Rethrow with a more user-friendly message
      throw Exception('Failed to upload avatar: ${e.toString()}');
    }
  }

  /// Update notification settings
  Future<Profile> updateNotificationSettings(
      String userId, NotificationSettings settings) async {
    try {
      // Ensure the profile exists
      await getProfile(userId);

      // Update with new settings
      return await upsertProfile(
        id: userId,
        notificationSettings: settings,
      );
    } catch (e) {
      debugPrint('Error updating notification settings: $e');
      throw Exception(
          'Failed to update notification settings: ${e.toString()}');
    }
  }

  /// Update privacy settings
  Future<Profile> updatePrivacySettings(
      String userId, PrivacySettings settings) async {
    try {
      // Ensure the profile exists
      await getProfile(userId);

      // Update with new settings
      return await upsertProfile(
        id: userId,
        privacySettings: settings,
      );
    } catch (e) {
      debugPrint('Error updating privacy settings: $e');
      throw Exception('Failed to update privacy settings: ${e.toString()}');
    }
  }

  /// Update theme mode
  Future<Profile> updateThemeMode(String userId, ThemeMode themeMode) async {
    try {
      // Ensure the profile exists
      await getProfile(userId);

      // Update with new theme mode
      return await upsertProfile(
        id: userId,
        themeMode: themeMode,
      );
    } catch (e) {
      debugPrint('Error updating theme mode: $e');
      throw Exception('Failed to update theme mode: ${e.toString()}');
    }
  }

  /// Update user interests
  Future<Profile> updateInterests(String userId, List<String> interests) async {
    try {
      // Ensure the profile exists
      await getProfile(userId);

      // Update with new interests
      return await upsertProfile(
        id: userId,
        interests: interests,
      );
    } catch (e) {
      debugPrint('Error updating interests: $e');
      throw Exception('Failed to update interests: ${e.toString()}');
    }
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
    required int maxParticipants, // Now required
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    try {
      debugPrint('Creating pulse with location: ($latitude, $longitude)');

      // First, let's check if we have the stored procedure we need
      bool hasStoredProcedure = false;
      try {
        final procedures = await _client.rpc(
          'get_available_functions',
          params: {},
        );
        if (procedures is List) {
          hasStoredProcedure = procedures
              .any((p) => p.toString().contains('create_pulse_with_location'));
        }
      } catch (e) {
        debugPrint('Error checking for stored procedure: $e');
        // Continue with the fallback approach
      }

      if (hasStoredProcedure) {
        debugPrint('Using create_pulse_with_location stored procedure');
        // Use the stored procedure if available
        final result = await _client.rpc(
          'create_pulse_with_location',
          params: {
            'creator_id_param': userId,
            'title_param': title,
            'description_param': description,
            'activity_emoji_param': activityEmoji,
            'latitude_param': latitude,
            'longitude_param': longitude,
            'radius_param': radius,
            'start_time_param': startTime.toIso8601String(),
            'end_time_param': endTime.toIso8601String(),
            'max_participants_param': maxParticipants,
          },
        );

        if (result == null) {
          throw Exception('Failed to create pulse: No response from database');
        }

        // Process the result
        final Map<String, dynamic> pulseData;
        if (result is Map<String, dynamic>) {
          pulseData = result;
        } else if (result is List &&
            result.isNotEmpty &&
            result[0] is Map<String, dynamic>) {
          pulseData = result[0];
        } else {
          throw Exception('Unexpected response format from database: $result');
        }

        final pulseId = pulseData['id'];
        debugPrint('Pulse created with ID: $pulseId');

        // Automatically join the pulse as creator
        await joinPulse(pulseId);

        return Pulse.fromJson(pulseData);
      } else {
        debugPrint('Using direct SQL approach');
        // Fallback to direct SQL approach

        // Create a raw SQL query to insert the pulse with proper PostGIS handling
        final rawQuery = '''
        INSERT INTO pulses (
          creator_id, title, description, activity_emoji,
          location, radius, start_time, end_time,
          max_participants, is_active, created_at, updated_at
        ) VALUES (
          '$userId', '$title', '$description', ${activityEmoji != null ? "'$activityEmoji'" : 'NULL'},
          ST_SetSRID(ST_MakePoint($longitude, $latitude), 4326)::geography, $radius,
          '${startTime.toIso8601String()}', '${endTime.toIso8601String()}',
          $maxParticipants, true,
          NOW(), NOW()
        ) RETURNING id
        ''';

        // Execute the raw query
        final response = await _client.rpc(
          'execute_sql',
          params: {
            'query': rawQuery,
          },
        );

        // Extract the pulse ID
        String? pulseId;
        if (response is List && response.isNotEmpty) {
          pulseId = response[0]['id']?.toString();
        }

        if (pulseId == null) {
          throw Exception('Failed to create pulse: No ID returned');
        }

        debugPrint('Pulse created with ID: $pulseId');

        // Now get the pulse with coordinates
        final pulseResponse = await _client.rpc(
          'get_pulse_with_coordinates',
          params: {
            'pulse_id_param': pulseId,
          },
        ).single();

        if (pulseResponse == null) {
          throw Exception('Failed to retrieve created pulse');
        }

        // Verify the coordinates were stored correctly
        if (pulseResponse['longitude'] != null &&
            pulseResponse['latitude'] != null) {
          final storedLng = double.parse(pulseResponse['longitude'].toString());
          final storedLat = double.parse(pulseResponse['latitude'].toString());

          debugPrint(
              'Stored pulse coordinates: lat=$storedLat, lng=$storedLng');

          // Check if the coordinates match what we sent
          if ((storedLat - latitude).abs() > 0.0001 ||
              (storedLng - longitude).abs() > 0.0001) {
            debugPrint(
                'WARNING: Stored coordinates differ from input coordinates!');
          }
        } else {
          debugPrint('WARNING: No coordinates extracted from stored pulse');
          // Add coordinates manually
          pulseResponse['longitude'] = longitude;
          pulseResponse['latitude'] = latitude;
        }

        // Automatically join the pulse as creator
        await joinPulse(pulseId);

        return Pulse.fromJson(pulseResponse);
      }
    } catch (e) {
      debugPrint('Error creating pulse: $e');
      rethrow;
    }
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

      // Process the response which could be in different formats
      List<Map<String, dynamic>> pulseDataList = [];

      if (response is List) {
        for (var item in response) {
          if (item is Map<String, dynamic>) {
            pulseDataList.add(item);
          } else if (item is String) {
            // Try to parse as JSON if it's a string
            try {
              final Map<String, dynamic> jsonData = jsonDecode(item);
              pulseDataList.add(jsonData);
            } catch (e) {
              debugPrint('Error parsing JSON string: $e');
            }
          }
        }
      }

      debugPrint('Processed ${pulseDataList.length} pulse data items');

      // Convert each item to a Pulse
      final pulses = pulseDataList
          .map((item) {
            try {
              // Debug the location data
              debugPrint(
                  'Pulse ${item['id']} location data: ${item['location_text'] ?? item['location']}');
              debugPrint(
                  'Pulse ${item['id']} coordinates: lat=${item['latitude']}, lng=${item['longitude']}');

              // Create Pulse object
              final pulse = Pulse.fromJson(item);

              // Add distance if available
              if (item['distance_meters'] != null) {
                pulse.distanceMeters =
                    double.parse(item['distance_meters'].toString());
              }

              return pulse;
            } catch (e) {
              debugPrint('Error parsing pulse: $e');
              debugPrint('Problematic data: $item');
              return null;
            }
          })
          .where((pulse) => pulse != null)
          .cast<Pulse>()
          .toList();

      debugPrint('Successfully parsed ${pulses.length} pulses');
      return pulses;
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

        List<Map<String, dynamic>> pulseDataList = [];

        if (response is List) {
          for (var item in response) {
            if (item is Map<String, dynamic>) {
              pulseDataList.add(item);
            } else if (item is String) {
              try {
                final Map<String, dynamic> jsonData = jsonDecode(item);
                pulseDataList.add(jsonData);
              } catch (e) {
                debugPrint('Error parsing JSON string: $e');
              }
            }
          }

          // Filter pulses by distance manually
          final userPoint = LatLng(latitude, longitude);
          final nearbyPulses = <Pulse>[];

          for (final item in pulseDataList) {
            try {
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
  Future<Map<String, dynamic>> joinPulse(String pulseId) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Get the pulse to check its status
    final pulse = await getPulseById(pulseId);
    if (pulse == null) {
      throw Exception('Pulse not found');
    }

    // Check if the pulse is full
    if (pulse.isFull) {
      // Add to waiting list
      final nextPosition = await _client.rpc(
        'get_next_waiting_list_position',
        params: {
          'pulse_id_param': pulseId,
        },
      );

      await _client.from('pulse_waiting_list').insert({
        'pulse_id': pulseId,
        'user_id': userId,
        'position': nextPosition,
        'status': 'Waiting',
        'joined_at': DateTime.now().toIso8601String(),
      });

      return {
        'success': true,
        'message': 'Added to waiting list',
        'waitingList': true,
      };
    }

    // Add as participant
    await _client.from('pulse_participants').upsert({
      'pulse_id': pulseId,
      'user_id': userId,
      'status': 'active',
      'joined_at': DateTime.now().toIso8601String(),
      'left_at': null,
    });

    return {
      'success': true,
      'message': 'Joined successfully',
      'waitingList': false,
    };
  }

  /// Leave a pulse
  Future<bool> leavePulse(String pulseId) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Check if user is on waiting list
    final waitingListResponse = await _client
        .from('pulse_waiting_list')
        .select('id')
        .eq('pulse_id', pulseId)
        .eq('user_id', userId)
        .eq('status', 'Waiting');

    if (waitingListResponse.isNotEmpty) {
      // Leave waiting list
      await _client
          .from('pulse_waiting_list')
          .delete()
          .eq('pulse_id', pulseId)
          .eq('user_id', userId);
      return true;
    }

    // Leave as participant
    await _client
        .from('pulse_participants')
        .update({'status': 'left', 'left_at': DateTime.now().toIso8601String()})
        .eq('pulse_id', pulseId)
        .eq('user_id', userId);

    return true;
  }

  /// Get waiting list for a pulse
  Future<List<Map<String, dynamic>>> getWaitingList(String pulseId) async {
    final response = await _client
        .from('pulse_waiting_list')
        .select('*, profiles:user_id(id, username, display_name, avatar_url)')
        .eq('pulse_id', pulseId)
        .eq('status', 'Waiting')
        .order('position', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Get waiting list count for a pulse
  Future<int> getWaitingListCount(String pulseId) async {
    final response = await _client
        .from('pulse_waiting_list')
        .select('id')
        .eq('pulse_id', pulseId)
        .eq('status', 'Waiting');

    return response.length;
  }

  /// Check if user is on waiting list
  Future<bool> isUserOnWaitingList(String pulseId) async {
    final userId = currentUserId;
    if (userId == null) return false;

    final response = await _client
        .from('pulse_waiting_list')
        .select('id')
        .eq('pulse_id', pulseId)
        .eq('user_id', userId)
        .eq('status', 'Waiting');

    return response.isNotEmpty;
  }

  /// Get user's position on waiting list
  Future<int> getUserWaitingListPosition(String pulseId) async {
    final userId = currentUserId;
    if (userId == null) return 0;

    try {
      final response = await _client
          .from('pulse_waiting_list')
          .select('position')
          .eq('pulse_id', pulseId)
          .eq('user_id', userId)
          .eq('status', 'Waiting');

      // Handle case where user is not on waiting list (empty result)
      if (response.isEmpty) return 0;

      return response.first['position'] as int? ?? 0;
    } catch (e) {
      debugPrint('Error getting user waiting list position: $e');
      return 0;
    }
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

  /// Get pulses created by a specific user
  Future<List<Pulse>> getPulsesByCreator(String creatorId) async {
    try {
      // We need to use a raw query to extract coordinates
      final response = await _client.rpc(
        'get_pulses_with_coordinates',
        params: {
          'creator_id_param': creatorId,
        },
      );

      // Process the response which could be in different formats
      List<Map<String, dynamic>> pulseDataList = [];

      if (response is List) {
        for (var item in response) {
          if (item is Map<String, dynamic>) {
            pulseDataList.add(item);
          } else if (item is String) {
            // Try to parse as JSON if it's a string
            try {
              final Map<String, dynamic> jsonData = jsonDecode(item);
              pulseDataList.add(jsonData);
            } catch (e) {
              debugPrint('Error parsing JSON string: $e');
            }
          }
        }
      }

      debugPrint('Processed ${pulseDataList.length} created pulse data items');

      // Convert each item to a Pulse
      final pulses = pulseDataList
          .map((item) {
            try {
              return Pulse.fromJson(item);
            } catch (e) {
              debugPrint('Error parsing pulse: $e');
              debugPrint('Problematic data: $item');
              return null;
            }
          })
          .where((pulse) => pulse != null)
          .cast<Pulse>()
          .toList();

      return pulses;
    } catch (e) {
      debugPrint('Error fetching pulses by creator: $e');
      return [];
    }
  }

  /// Get pulses created by the current user
  Future<List<Pulse>> getCreatedPulses() async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    try {
      return await getPulsesByCreator(userId);
    } catch (e) {
      debugPrint('Error fetching created pulses: $e');
      rethrow;
    }
  }

  /// Search for pulses by title or description
  Future<List<Pulse>> searchPulses(String query) async {
    if (query.isEmpty) return [];

    try {
      debugPrint('Searching for pulses with query: $query');

      // Use a text search query with ILIKE for case-insensitive search
      final response = await _client.rpc(
        'get_pulses_with_coordinates',
        params: {},
      );

      // Process the response which could be in different formats
      List<Map<String, dynamic>> pulseDataList = [];

      if (response is List) {
        for (var item in response) {
          if (item is Map<String, dynamic>) {
            pulseDataList.add(item);
          } else if (item is String) {
            try {
              final Map<String, dynamic> jsonData = jsonDecode(item);
              pulseDataList.add(jsonData);
            } catch (e) {
              debugPrint('Error parsing JSON string: $e');
            }
          }
        }
      }

      // Filter pulses by title or description containing the query
      final filteredPulses = <Pulse>[];
      final lowerQuery = query.toLowerCase();

      for (final item in pulseDataList) {
        try {
          final pulse = Pulse.fromJson(item);

          // Check if title or description contains the query (case-insensitive)
          final titleMatch = pulse.title.toLowerCase().contains(lowerQuery);
          final descriptionMatch =
              pulse.description.toLowerCase().contains(lowerQuery);

          if (titleMatch || descriptionMatch) {
            filteredPulses.add(pulse);
          }
        } catch (e) {
          debugPrint('Error processing pulse in search: $e');
        }
      }

      debugPrint(
          'Found ${filteredPulses.length} pulses matching query: $query');
      return filteredPulses;
    } catch (e) {
      debugPrint('Error searching pulses: $e');
      return [];
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

      if (participantResponse.isEmpty) {
        return [];
      }

      // Extract pulse IDs
      final pulseIds = participantResponse
          .map<String>((item) => item['pulse_id'] as String)
          .toList();

      // Get pulse details with extracted coordinates
      final pulsesResponse = await _client.rpc(
        'get_joined_pulses_with_coordinates',
        params: {
          'pulse_ids': pulseIds,
        },
      );

      // Process the response
      List<Map<String, dynamic>> pulseDataList = [];

      if (pulsesResponse is List) {
        for (var item in pulsesResponse) {
          if (item is Map<String, dynamic>) {
            pulseDataList.add(item);
          } else if (item is String) {
            try {
              final Map<String, dynamic> jsonData = jsonDecode(item);
              pulseDataList.add(jsonData);
            } catch (e) {
              debugPrint('Error parsing JSON string: $e');
            }
          }
        }
      }

      // Convert to Pulse objects
      final pulses = pulseDataList
          .map((item) {
            try {
              return Pulse.fromJson(item);
            } catch (e) {
              debugPrint('Error parsing pulse: $e');
              return null;
            }
          })
          .where((pulse) => pulse != null)
          .cast<Pulse>()
          .toList();

      return pulses;
    } catch (e) {
      debugPrint('Error fetching joined pulses: $e');
      return [];
    }
  }

  /// Get pulses where the current user has participated (either as creator or participant)
  Future<List<Pulse>> getParticipatedPulses() async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Get pulses created by the user
      final createdPulses = await getCreatedPulses();

      // Get pulses joined by the user
      final joinedPulses = await getJoinedPulses();

      // Combine and remove duplicates
      final Map<String, Pulse> pulsesMap = {};

      for (final pulse in createdPulses) {
        pulsesMap[pulse.id] = pulse;
      }

      for (final pulse in joinedPulses) {
        pulsesMap[pulse.id] = pulse;
      }

      return pulsesMap.values.toList();
    } catch (e) {
      debugPrint('Error fetching participated pulses: $e');
      return [];
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
      );

      // Process the response which could be in different formats
      Map<String, dynamic>? pulseData;

      if (response is List && response.isNotEmpty) {
        var item = response[0];
        if (item is Map<String, dynamic>) {
          pulseData = item;
        } else if (item is String) {
          // Try to parse as JSON if it's a string
          try {
            pulseData = jsonDecode(item);
          } catch (e) {
            debugPrint('Error parsing JSON string: $e');
          }
        }
      } else if (response is Map<String, dynamic>) {
        pulseData = response;
      }

      if (pulseData != null) {
        // Add creator_name from the joined profiles table
        if (pulseData['profiles'] != null &&
            pulseData['profiles']['display_name'] != null) {
          pulseData['creator_name'] = pulseData['profiles']['display_name'];
        }

        // Parse the pulse
        final pulse = Pulse.fromJson(pulseData);
        return pulse;
      }

      return null;
    } catch (e) {
      debugPrint('Error fetching pulse by ID: $e');
      return null;
    }
  }

  /// Get a pulse by share code
  Future<Pulse?> getPulseByShareCode(String shareCode) async {
    try {
      debugPrint('Fetching pulse with share code: $shareCode');

      // Get the pulse details using the find_pulse_by_share_code function
      final response = await _client.rpc(
        'find_pulse_by_share_code',
        params: {
          'code': shareCode,
        },
      );

      // Process the response
      if (response is List && response.isNotEmpty) {
        var item = response[0];
        if (item is Map<String, dynamic>) {
          return Pulse.fromJson(item);
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error fetching pulse by share code: $e');
      return null;
    }
  }

  /// Check if a string is a valid pulse share code
  Future<bool> isValidPulseCode(String code) async {
    try {
      // Clean the code (remove spaces, make uppercase)
      final cleanCode = code.trim().toUpperCase();

      // Check if the code matches the expected format (6-8 alphanumeric characters)
      if (!RegExp(r'^[A-Z0-9]{6,8}$').hasMatch(cleanCode)) {
        return false;
      }

      // Check if the code exists in the database
      final pulse = await getPulseByShareCode(cleanCode);
      return pulse != null;
    } catch (e) {
      debugPrint('Error checking pulse code: $e');
      return false;
    }
  }
}
