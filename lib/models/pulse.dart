import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Status of a pulse
enum PulseStatus {
  open,
  full,
}

/// Model class for a Pulse (meetup)
class Pulse {
  final String id;
  final String creatorId;
  final String? creatorName;
  final String title;
  final String description;
  final String? activityEmoji;
  final LatLng location;
  final int radius;
  final DateTime startTime;
  final DateTime endTime;
  final int? maxParticipants;
  final int participantCount;
  final bool isActive;
  final PulseStatus status;
  final int waitingListCount;
  double? distanceMeters;
  final DateTime createdAt;
  final DateTime updatedAt;

  Pulse({
    required this.id,
    required this.creatorId,
    this.creatorName,
    required this.title,
    required this.description,
    this.activityEmoji,
    required this.location,
    required this.radius,
    required this.startTime,
    required this.endTime,
    this.maxParticipants,
    this.participantCount = 0,
    this.isActive = true,
    this.status = PulseStatus.open,
    this.waitingListCount = 0,
    this.distanceMeters,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a Pulse from JSON data
  factory Pulse.fromJson(Map<String, dynamic> json) {
    // Debug the incoming JSON
    debugPrint('Creating Pulse from JSON: ${json.keys.join(', ')}');

    // Handle location which could be in different formats
    LatLng locationFromJson() {
      try {
        // Debug the location data
        debugPrint('Location data: ${json['location']}');
        debugPrint(
            'Latitude: ${json['latitude']}, Longitude: ${json['longitude']}');

        // First priority: Use extracted latitude and longitude if available
        if (json['latitude'] != null && json['longitude'] != null) {
          final lat = double.parse(json['latitude'].toString());
          final lng = double.parse(json['longitude'].toString());
          debugPrint('Using extracted coordinates: ($lat, $lng)');
          return LatLng(lat, lng);
        }

        // Second priority: Parse from PostGIS POINT format or location_text
        final locationString = json['location_text'] ?? json['location'];
        if (locationString is String &&
            locationString.toString().startsWith('POINT')) {
          // Parse from PostGIS POINT format: 'POINT(longitude latitude)'
          final pointString = locationString
              .toString()
              .replaceAll('POINT(', '')
              .replaceAll(')', '');
          final coordinates = pointString.split(' ');

          if (coordinates.length >= 2) {
            final lng = double.parse(coordinates[0].trim());
            final lat = double.parse(coordinates[1].trim());
            debugPrint('Parsed from POINT format: ($lat, $lng)');
            return LatLng(lat, lng);
          }
        }

        // Default to (0,0) if no valid location
        debugPrint('No valid location found in JSON, using default (0,0)');
        return const LatLng(0, 0);
      } catch (e) {
        debugPrint('Error parsing location: $e');
        return const LatLng(0, 0);
      }
    }

    // Parse date safely
    DateTime parseDate(String? dateStr, {DateTime? defaultValue}) {
      if (dateStr == null) return defaultValue ?? DateTime.now();
      try {
        return DateTime.parse(dateStr);
      } catch (e) {
        debugPrint('Error parsing date "$dateStr": $e');
        return defaultValue ?? DateTime.now();
      }
    }

    // Parse number safely
    T parseNumber<T extends num>(dynamic value, {T? defaultValue}) {
      if (value == null) return defaultValue as T;
      try {
        if (T == int) {
          return int.parse(value.toString()) as T;
        } else if (T == double) {
          return double.parse(value.toString()) as T;
        }
        return defaultValue as T;
      } catch (e) {
        debugPrint('Error parsing number "$value": $e');
        return defaultValue as T;
      }
    }

    try {
      // Parse pulse status
      PulseStatus parseStatus(String? statusStr) {
        switch (statusStr?.toLowerCase()) {
          case 'full':
            return PulseStatus.full;
          case 'open':
          default:
            return PulseStatus.open;
        }
      }

      return Pulse(
        id: json['id']?.toString() ?? 'unknown',
        creatorId: json['creator_id']?.toString() ?? 'unknown',
        creatorName: json['creator_name']?.toString(),
        title: json['title']?.toString() ?? 'Untitled Pulse',
        description: json['description']?.toString() ?? '',
        activityEmoji: json['activity_emoji']?.toString(),
        location: locationFromJson(),
        radius: parseNumber<int>(json['radius'], defaultValue: 500),
        startTime: parseDate(json['start_time']?.toString(),
            defaultValue: DateTime.now()),
        endTime: parseDate(json['end_time']?.toString(),
            defaultValue: DateTime.now().add(const Duration(hours: 1))),
        maxParticipants: json['max_participants'] != null
            ? parseNumber<int>(json['max_participants'])
            : null,
        participantCount:
            parseNumber<int>(json['participant_count'], defaultValue: 0),
        isActive: json['is_active'] == true,
        status: parseStatus(json['status']?.toString()),
        waitingListCount:
            parseNumber<int>(json['waiting_list_count'], defaultValue: 0),
        distanceMeters: json['distance_meters'] != null
            ? parseNumber<double>(json['distance_meters'])
            : null,
        createdAt: parseDate(json['created_at']?.toString()),
        updatedAt: parseDate(json['updated_at']?.toString()),
      );
    } catch (e) {
      debugPrint('Error creating Pulse from JSON: $e');
      // Return a default Pulse as fallback
      return Pulse(
        id: json['id']?.toString() ?? 'error',
        creatorId: json['creator_id']?.toString() ?? 'unknown',
        title: 'Error Loading Pulse',
        description: 'There was an error loading this pulse.',
        location: const LatLng(0, 0),
        radius: 500,
        startTime: DateTime.now(),
        endTime: DateTime.now().add(const Duration(hours: 1)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
  }

  /// Convert Pulse to JSON
  Map<String, dynamic> toJson() {
    String statusToString(PulseStatus status) {
      switch (status) {
        case PulseStatus.full:
          return 'Full';
        case PulseStatus.open:
          return 'Open';
      }
    }

    return {
      'id': id,
      'creator_id': creatorId,
      'title': title,
      'description': description,
      'activity_emoji': activityEmoji,
      'location': 'POINT(${location.longitude} ${location.latitude})',
      'radius': radius,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'max_participants': maxParticipants,
      'is_active': isActive,
      'status': statusToString(status),
      'participant_count': participantCount,
      'waiting_list_count': waitingListCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy of Pulse with updated fields
  Pulse copyWith({
    String? title,
    String? description,
    String? activityEmoji,
    LatLng? location,
    int? radius,
    DateTime? startTime,
    DateTime? endTime,
    int? maxParticipants,
    int? participantCount,
    bool? isActive,
    PulseStatus? status,
    int? waitingListCount,
  }) {
    return Pulse(
      id: id,
      creatorId: creatorId,
      creatorName: creatorName,
      title: title ?? this.title,
      description: description ?? this.description,
      activityEmoji: activityEmoji ?? this.activityEmoji,
      location: location ?? this.location,
      radius: radius ?? this.radius,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      participantCount: participantCount ?? this.participantCount,
      isActive: isActive ?? this.isActive,
      status: status ?? this.status,
      waitingListCount: waitingListCount ?? this.waitingListCount,
      distanceMeters: distanceMeters,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// Check if the pulse is currently active
  bool get isCurrentlyActive =>
      isActive &&
      startTime.isBefore(DateTime.now()) &&
      endTime.isAfter(DateTime.now());

  /// Check if the pulse is upcoming
  bool get isUpcoming => isActive && startTime.isAfter(DateTime.now());

  /// Check if the pulse has ended
  bool get hasEnded => !isActive || endTime.isBefore(DateTime.now());

  /// Get the formatted distance string
  String get formattedDistance {
    if (distanceMeters == null) return '';
    if (distanceMeters! < 1000) {
      return '${distanceMeters!.round()} m';
    } else {
      return '${(distanceMeters! / 1000).toStringAsFixed(1)} km';
    }
  }

  /// Check if the pulse is full
  bool get isFull => status == PulseStatus.full;

  /// Check if the pulse has a waiting list
  bool get hasWaitingList => waitingListCount > 0;

  /// Get the formatted participant count string
  String get formattedParticipantCount {
    if (maxParticipants == null) {
      return '$participantCount participants';
    } else {
      return '$participantCount/$maxParticipants participants';
    }
  }

  /// Get the capacity percentage (0-100)
  int get capacityPercentage {
    if (maxParticipants == null || maxParticipants == 0) return 0;
    return (participantCount / maxParticipants! * 100).round().clamp(0, 100);
  }
}
