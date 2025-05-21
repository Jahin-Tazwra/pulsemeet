import 'package:flutter/foundation.dart' show debugPrint;

/// Status of a waiting list entry
enum WaitingListStatus {
  waiting,
  promoted,
  removed,
}

/// Model class for a waiting list entry
class WaitingListEntry {
  final String id;
  final String pulseId;
  final String userId;
  final DateTime joinedAt;
  final int position;
  final WaitingListStatus status;
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  WaitingListEntry({
    required this.id,
    required this.pulseId,
    required this.userId,
    required this.joinedAt,
    required this.position,
    required this.status,
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  /// Create a WaitingListEntry from JSON data
  factory WaitingListEntry.fromJson(Map<String, dynamic> json) {
    try {
      // Parse status
      WaitingListStatus parseStatus(String? statusStr) {
        switch (statusStr?.toLowerCase()) {
          case 'promoted':
            return WaitingListStatus.promoted;
          case 'removed':
            return WaitingListStatus.removed;
          case 'waiting':
          default:
            return WaitingListStatus.waiting;
        }
      }

      return WaitingListEntry(
        id: json['id']?.toString() ?? 'unknown',
        pulseId: json['pulse_id']?.toString() ?? 'unknown',
        userId: json['user_id']?.toString() ?? 'unknown',
        joinedAt: json['joined_at'] != null
            ? DateTime.parse(json['joined_at'].toString())
            : DateTime.now(),
        position: json['position'] != null
            ? int.tryParse(json['position'].toString()) ?? 0
            : 0,
        status: parseStatus(json['status']?.toString()),
        username: json['username']?.toString(),
        displayName: json['display_name']?.toString(),
        avatarUrl: json['avatar_url']?.toString(),
      );
    } catch (e) {
      debugPrint('Error creating WaitingListEntry from JSON: $e');
      // Return a default entry as fallback
      return WaitingListEntry(
        id: json['id']?.toString() ?? 'error',
        pulseId: json['pulse_id']?.toString() ?? 'unknown',
        userId: json['user_id']?.toString() ?? 'unknown',
        joinedAt: DateTime.now(),
        position: 0,
        status: WaitingListStatus.waiting,
      );
    }
  }

  /// Convert WaitingListEntry to JSON
  Map<String, dynamic> toJson() {
    String statusToString(WaitingListStatus status) {
      switch (status) {
        case WaitingListStatus.promoted:
          return 'Promoted';
        case WaitingListStatus.removed:
          return 'Removed';
        case WaitingListStatus.waiting:
          return 'Waiting';
      }
    }

    return {
      'id': id,
      'pulse_id': pulseId,
      'user_id': userId,
      'joined_at': joinedAt.toIso8601String(),
      'position': position,
      'status': statusToString(status),
    };
  }

  /// Create a copy of WaitingListEntry with updated fields
  WaitingListEntry copyWith({
    String? id,
    String? pulseId,
    String? userId,
    DateTime? joinedAt,
    int? position,
    WaitingListStatus? status,
    String? username,
    String? displayName,
    String? avatarUrl,
  }) {
    return WaitingListEntry(
      id: id ?? this.id,
      pulseId: pulseId ?? this.pulseId,
      userId: userId ?? this.userId,
      joinedAt: joinedAt ?? this.joinedAt,
      position: position ?? this.position,
      status: status ?? this.status,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
