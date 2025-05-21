import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;

/// Model class for user profile
class Profile {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? phoneNumber;
  final String? bio;
  final String? email;
  final bool isVerified;
  final String verificationStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastSeenAt;
  final NotificationSettings notificationSettings;
  final PrivacySettings privacySettings;
  final ThemeMode themeMode;
  final String? location;
  final List<String> interests;
  final double averageRating;
  final int totalRatings;

  Profile({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.phoneNumber,
    this.bio,
    this.email,
    this.isVerified = false,
    this.verificationStatus = 'unverified',
    required this.createdAt,
    required this.updatedAt,
    required this.lastSeenAt,
    NotificationSettings? notificationSettings,
    PrivacySettings? privacySettings,
    this.themeMode = ThemeMode.system,
    this.location,
    List<String>? interests,
    this.averageRating = 0.0,
    this.totalRatings = 0,
  })  : notificationSettings = notificationSettings ?? NotificationSettings(),
        privacySettings = privacySettings ?? PrivacySettings(),
        interests = interests ?? [];

  /// Create a Profile from JSON data
  factory Profile.fromJson(Map<String, dynamic> json) {
    // Handle potentially null date fields
    DateTime parseDateTime(String? dateStr) {
      if (dateStr == null) return DateTime.now();
      try {
        return DateTime.parse(dateStr);
      } catch (e) {
        debugPrint('Error parsing date: $e');
        return DateTime.now();
      }
    }

    return Profile(
      id: json['id'] ?? 'unknown',
      username: json['username'],
      displayName: json['display_name'],
      avatarUrl: json['avatar_url'],
      phoneNumber: json['phone_number'],
      bio: json['bio'],
      email: json['email'],
      isVerified: json['is_verified'] ?? false,
      verificationStatus: json['verification_status'] ?? 'unverified',
      createdAt: parseDateTime(json['created_at']?.toString()),
      updatedAt: parseDateTime(json['updated_at']?.toString()),
      lastSeenAt: parseDateTime(json['last_seen_at']?.toString()),
      notificationSettings: json['notification_settings'] != null
          ? NotificationSettings.fromJson(
              json['notification_settings'] is String
                  ? jsonDecode(json['notification_settings'])
                  : json['notification_settings'])
          : null,
      privacySettings: json['privacy_settings'] != null
          ? PrivacySettings.fromJson(json['privacy_settings'] is String
              ? jsonDecode(json['privacy_settings'])
              : json['privacy_settings'])
          : null,
      themeMode: _parseThemeMode(json['theme_mode']),
      location: json['location'],
      interests: json['interests'] != null
          ? (json['interests'] is String
              ? (jsonDecode(json['interests']) as List).cast<String>()
              : (json['interests'] as List).cast<String>())
          : null,
      averageRating: json['average_rating'] != null
          ? double.tryParse(json['average_rating'].toString()) ?? 0.0
          : 0.0,
      totalRatings: json['total_ratings'] ?? 0,
    );
  }

  /// Parse theme mode from string
  static ThemeMode _parseThemeMode(dynamic value) {
    if (value == null) return ThemeMode.system;

    switch (value.toString()) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  /// Convert theme mode to string
  static String _themeModeTString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// Convert Profile to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'phone_number': phoneNumber,
      'bio': bio,
      'email': email,
      'is_verified': isVerified,
      'verification_status': verificationStatus,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_seen_at': lastSeenAt.toIso8601String(),
      'notification_settings': jsonEncode(notificationSettings.toJson()),
      'privacy_settings': jsonEncode(privacySettings.toJson()),
      'theme_mode': _themeModeTString(themeMode),
      'location': location,
      'interests': jsonEncode(interests),
      'average_rating': averageRating,
      'total_ratings': totalRatings,
    };
  }

  /// Create a copy of Profile with updated fields
  Profile copyWith({
    String? username,
    String? displayName,
    String? avatarUrl,
    String? phoneNumber,
    String? bio,
    String? email,
    bool? isVerified,
    String? verificationStatus,
    DateTime? lastSeenAt,
    NotificationSettings? notificationSettings,
    PrivacySettings? privacySettings,
    ThemeMode? themeMode,
    String? location,
    List<String>? interests,
    double? averageRating,
    int? totalRatings,
  }) {
    return Profile(
      id: id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      bio: bio ?? this.bio,
      email: email ?? this.email,
      isVerified: isVerified ?? this.isVerified,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      notificationSettings: notificationSettings ?? this.notificationSettings,
      privacySettings: privacySettings ?? this.privacySettings,
      themeMode: themeMode ?? this.themeMode,
      location: location ?? this.location,
      interests: interests ?? this.interests,
      averageRating: averageRating ?? this.averageRating,
      totalRatings: totalRatings ?? this.totalRatings,
    );
  }
}

/// Notification settings for a user
class NotificationSettings {
  final bool newPulseNotifications;
  final bool messageNotifications;
  final bool mentionNotifications;
  final bool pulseUpdatesNotifications;
  final bool nearbyPulsesNotifications;
  final bool favoriteHostNotifications;
  final bool connectionNotifications;
  final bool directMessageNotifications;
  final bool emailNotifications;
  final bool pushNotifications;

  NotificationSettings({
    this.newPulseNotifications = true,
    this.messageNotifications = true,
    this.mentionNotifications = true,
    this.pulseUpdatesNotifications = true,
    this.nearbyPulsesNotifications = true,
    this.favoriteHostNotifications = true,
    this.connectionNotifications = true,
    this.directMessageNotifications = true,
    this.emailNotifications = false,
    this.pushNotifications = true,
  });

  /// Create NotificationSettings from JSON
  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      newPulseNotifications: json['new_pulse_notifications'] ?? true,
      messageNotifications: json['message_notifications'] ?? true,
      mentionNotifications: json['mention_notifications'] ?? true,
      pulseUpdatesNotifications: json['pulse_updates_notifications'] ?? true,
      nearbyPulsesNotifications: json['nearby_pulses_notifications'] ?? true,
      favoriteHostNotifications: json['favorite_host_notifications'] ?? true,
      connectionNotifications: json['connection_notifications'] ?? true,
      directMessageNotifications: json['direct_message_notifications'] ?? true,
      emailNotifications: json['email_notifications'] ?? false,
      pushNotifications: json['push_notifications'] ?? true,
    );
  }

  /// Convert NotificationSettings to JSON
  Map<String, dynamic> toJson() {
    return {
      'new_pulse_notifications': newPulseNotifications,
      'message_notifications': messageNotifications,
      'mention_notifications': mentionNotifications,
      'pulse_updates_notifications': pulseUpdatesNotifications,
      'nearby_pulses_notifications': nearbyPulsesNotifications,
      'favorite_host_notifications': favoriteHostNotifications,
      'connection_notifications': connectionNotifications,
      'direct_message_notifications': directMessageNotifications,
      'email_notifications': emailNotifications,
      'push_notifications': pushNotifications,
    };
  }

  /// Create a copy of NotificationSettings with updated fields
  NotificationSettings copyWith({
    bool? newPulseNotifications,
    bool? messageNotifications,
    bool? mentionNotifications,
    bool? pulseUpdatesNotifications,
    bool? nearbyPulsesNotifications,
    bool? favoriteHostNotifications,
    bool? connectionNotifications,
    bool? directMessageNotifications,
    bool? emailNotifications,
    bool? pushNotifications,
  }) {
    return NotificationSettings(
      newPulseNotifications:
          newPulseNotifications ?? this.newPulseNotifications,
      messageNotifications: messageNotifications ?? this.messageNotifications,
      mentionNotifications: mentionNotifications ?? this.mentionNotifications,
      pulseUpdatesNotifications:
          pulseUpdatesNotifications ?? this.pulseUpdatesNotifications,
      nearbyPulsesNotifications:
          nearbyPulsesNotifications ?? this.nearbyPulsesNotifications,
      favoriteHostNotifications:
          favoriteHostNotifications ?? this.favoriteHostNotifications,
      connectionNotifications:
          connectionNotifications ?? this.connectionNotifications,
      directMessageNotifications:
          directMessageNotifications ?? this.directMessageNotifications,
      emailNotifications: emailNotifications ?? this.emailNotifications,
      pushNotifications: pushNotifications ?? this.pushNotifications,
    );
  }
}

/// Privacy settings for a user
class PrivacySettings {
  final bool showOnlineStatus;
  final bool showLastSeen;
  final bool showProfileToNonParticipants;
  final bool allowMessagesFromNonParticipants;
  final bool shareLocationWithParticipants;
  final LocationSharingMode locationSharingMode;

  PrivacySettings({
    this.showOnlineStatus = true,
    this.showLastSeen = true,
    this.showProfileToNonParticipants = true,
    this.allowMessagesFromNonParticipants = false,
    this.shareLocationWithParticipants = true,
    this.locationSharingMode = LocationSharingMode.whileActive,
  });

  /// Create PrivacySettings from JSON
  factory PrivacySettings.fromJson(Map<String, dynamic> json) {
    return PrivacySettings(
      showOnlineStatus: json['show_online_status'] ?? true,
      showLastSeen: json['show_last_seen'] ?? true,
      showProfileToNonParticipants:
          json['show_profile_to_non_participants'] ?? true,
      allowMessagesFromNonParticipants:
          json['allow_messages_from_non_participants'] ?? false,
      shareLocationWithParticipants:
          json['share_location_with_participants'] ?? true,
      locationSharingMode:
          _parseLocationSharingMode(json['location_sharing_mode']),
    );
  }

  /// Parse location sharing mode from string
  static LocationSharingMode _parseLocationSharingMode(dynamic value) {
    if (value == null) return LocationSharingMode.whileActive;

    switch (value.toString()) {
      case 'always':
        return LocationSharingMode.always;
      case 'never':
        return LocationSharingMode.never;
      default:
        return LocationSharingMode.whileActive;
    }
  }

  /// Convert location sharing mode to string
  static String _locationSharingModeToString(LocationSharingMode mode) {
    switch (mode) {
      case LocationSharingMode.always:
        return 'always';
      case LocationSharingMode.never:
        return 'never';
      case LocationSharingMode.whileActive:
        return 'while_active';
    }
  }

  /// Convert PrivacySettings to JSON
  Map<String, dynamic> toJson() {
    return {
      'show_online_status': showOnlineStatus,
      'show_last_seen': showLastSeen,
      'show_profile_to_non_participants': showProfileToNonParticipants,
      'allow_messages_from_non_participants': allowMessagesFromNonParticipants,
      'share_location_with_participants': shareLocationWithParticipants,
      'location_sharing_mode':
          _locationSharingModeToString(locationSharingMode),
    };
  }

  /// Create a copy of PrivacySettings with updated fields
  PrivacySettings copyWith({
    bool? showOnlineStatus,
    bool? showLastSeen,
    bool? showProfileToNonParticipants,
    bool? allowMessagesFromNonParticipants,
    bool? shareLocationWithParticipants,
    LocationSharingMode? locationSharingMode,
  }) {
    return PrivacySettings(
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      showLastSeen: showLastSeen ?? this.showLastSeen,
      showProfileToNonParticipants:
          showProfileToNonParticipants ?? this.showProfileToNonParticipants,
      allowMessagesFromNonParticipants: allowMessagesFromNonParticipants ??
          this.allowMessagesFromNonParticipants,
      shareLocationWithParticipants:
          shareLocationWithParticipants ?? this.shareLocationWithParticipants,
      locationSharingMode: locationSharingMode ?? this.locationSharingMode,
    );
  }
}

/// Location sharing mode enum
enum LocationSharingMode {
  always,
  whileActive,
  never,
}

/// Theme mode enum
enum ThemeMode {
  system,
  light,
  dark,
}
