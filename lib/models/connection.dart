import 'package:pulsemeet/models/profile.dart';

/// Status of a connection between users
enum ConnectionStatus {
  pending,
  accepted,
  declined,
  blocked,
}

/// Model class for user connections
class Connection {
  final String id;
  final String requesterId;
  final String receiverId;
  final ConnectionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Additional fields for UI display
  final Profile? requesterProfile;
  final Profile? receiverProfile;
  
  Connection({
    required this.id,
    required this.requesterId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.requesterProfile,
    this.receiverProfile,
  });
  
  /// Create Connection from JSON
  factory Connection.fromJson(Map<String, dynamic> json) {
    return Connection(
      id: json['id'],
      requesterId: json['requester_id'],
      receiverId: json['receiver_id'],
      status: _parseConnectionStatus(json['status']),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      requesterProfile: json['requester_profile'] != null 
          ? Profile.fromJson(json['requester_profile']) 
          : null,
      receiverProfile: json['receiver_profile'] != null 
          ? Profile.fromJson(json['receiver_profile']) 
          : null,
    );
  }
  
  /// Convert Connection to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'requester_id': requesterId,
      'receiver_id': receiverId,
      'status': status.toString().split('.').last,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
  
  /// Create a copy of Connection with updated fields
  Connection copyWith({
    String? id,
    String? requesterId,
    String? receiverId,
    ConnectionStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    Profile? requesterProfile,
    Profile? receiverProfile,
  }) {
    return Connection(
      id: id ?? this.id,
      requesterId: requesterId ?? this.requesterId,
      receiverId: receiverId ?? this.receiverId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      requesterProfile: requesterProfile ?? this.requesterProfile,
      receiverProfile: receiverProfile ?? this.receiverProfile,
    );
  }
  
  /// Get the other user's ID (not the current user)
  String getOtherUserId(String currentUserId) {
    return requesterId == currentUserId ? receiverId : requesterId;
  }
  
  /// Get the other user's profile (not the current user)
  Profile? getOtherUserProfile(String currentUserId) {
    return requesterId == currentUserId ? receiverProfile : requesterProfile;
  }
  
  /// Check if the connection is with a specific user
  bool isWithUser(String userId) {
    return requesterId == userId || receiverId == userId;
  }
  
  /// Check if the connection is pending
  bool get isPending => status == ConnectionStatus.pending;
  
  /// Check if the connection is accepted
  bool get isAccepted => status == ConnectionStatus.accepted;
  
  /// Check if the connection is declined
  bool get isDeclined => status == ConnectionStatus.declined;
  
  /// Check if the connection is blocked
  bool get isBlocked => status == ConnectionStatus.blocked;
  
  /// Parse connection status from string
  static ConnectionStatus _parseConnectionStatus(String status) {
    switch (status) {
      case 'pending':
        return ConnectionStatus.pending;
      case 'accepted':
        return ConnectionStatus.accepted;
      case 'declined':
        return ConnectionStatus.declined;
      case 'blocked':
        return ConnectionStatus.blocked;
      default:
        return ConnectionStatus.pending;
    }
  }
}
