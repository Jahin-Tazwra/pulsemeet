/// Model class for user profile
class Profile {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? phoneNumber;
  final String? bio;
  final bool isVerified;
  final String verificationStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastSeenAt;

  Profile({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.phoneNumber,
    this.bio,
    this.isVerified = false,
    this.verificationStatus = 'unverified',
    required this.createdAt,
    required this.updatedAt,
    required this.lastSeenAt,
  });

  /// Create a Profile from JSON data
  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'],
      username: json['username'],
      displayName: json['display_name'],
      avatarUrl: json['avatar_url'],
      phoneNumber: json['phone_number'],
      bio: json['bio'],
      isVerified: json['is_verified'] ?? false,
      verificationStatus: json['verification_status'] ?? 'unverified',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      lastSeenAt: DateTime.parse(json['last_seen_at']),
    );
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
      'is_verified': isVerified,
      'verification_status': verificationStatus,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_seen_at': lastSeenAt.toIso8601String(),
    };
  }

  /// Create a copy of Profile with updated fields
  Profile copyWith({
    String? username,
    String? displayName,
    String? avatarUrl,
    String? phoneNumber,
    String? bio,
    bool? isVerified,
    String? verificationStatus,
    DateTime? lastSeenAt,
  }) {
    return Profile(
      id: id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      bio: bio ?? this.bio,
      isVerified: isVerified ?? this.isVerified,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}
