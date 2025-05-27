import 'package:json_annotation/json_annotation.dart';

part 'conversation.g.dart';

/// Enum for conversation types
enum ConversationType {
  @JsonValue('pulse_group')
  pulseGroup,
  @JsonValue('direct_message')
  directMessage,
  @JsonValue('group_chat')
  groupChat,
}

/// Model class for conversations (unified for pulse groups and DMs)
@JsonSerializable()
class Conversation {
  final String id;
  final ConversationType type;
  final String? title;
  final String? description;
  @JsonKey(name: 'avatar_url')
  final String? avatarUrl;
  @JsonKey(name: 'pulse_id')
  final String? pulseId; // Only for pulse groups
  @JsonKey(name: 'created_by')
  final String? createdBy;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;
  @JsonKey(name: 'last_message_at')
  final DateTime? lastMessageAt;
  @JsonKey(name: 'is_archived')
  final bool isArchived;
  @JsonKey(name: 'is_muted')
  final bool isMuted;
  final Map<String, dynamic> settings;
  @JsonKey(name: 'encryption_enabled')
  final bool encryptionEnabled;
  @JsonKey(name: 'encryption_key_id')
  final String? encryptionKeyId;

  // Runtime properties (not stored in DB)
  final int? unreadCount;
  final String? lastMessagePreview;
  final List<ConversationParticipant>? participants;

  const Conversation({
    required this.id,
    required this.type,
    this.title,
    this.description,
    this.avatarUrl,
    this.pulseId,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageAt,
    this.isArchived = false,
    this.isMuted = false,
    this.settings = const {},
    this.encryptionEnabled = true,
    this.encryptionKeyId,
    this.unreadCount,
    this.lastMessagePreview,
    this.participants,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) =>
      _$ConversationFromJson(json);

  Map<String, dynamic> toJson() => _$ConversationToJson(this);

  Conversation copyWith({
    String? id,
    ConversationType? type,
    String? title,
    String? description,
    String? avatarUrl,
    String? pulseId,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastMessageAt,
    bool? isArchived,
    bool? isMuted,
    Map<String, dynamic>? settings,
    bool? encryptionEnabled,
    String? encryptionKeyId,
    int? unreadCount,
    String? lastMessagePreview,
    List<ConversationParticipant>? participants,
  }) {
    return Conversation(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      pulseId: pulseId ?? this.pulseId,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      isArchived: isArchived ?? this.isArchived,
      isMuted: isMuted ?? this.isMuted,
      settings: settings ?? this.settings,
      encryptionEnabled: encryptionEnabled ?? this.encryptionEnabled,
      encryptionKeyId: encryptionKeyId ?? this.encryptionKeyId,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      participants: participants ?? this.participants,
    );
  }

  /// Get display title for the conversation
  String getDisplayTitle(String currentUserId) {
    if (title != null && title!.isNotEmpty) {
      return title!;
    }

    switch (type) {
      case ConversationType.pulseGroup:
        return 'Pulse Chat';
      case ConversationType.directMessage:
        if (participants != null && participants!.isNotEmpty) {
          final otherParticipant = participants!.firstWhere(
              (p) => p.userId != currentUserId,
              orElse: () => participants!.first);
          return otherParticipant.displayName ??
              otherParticipant.username ??
              'Unknown User';
        }
        return 'Direct Message';
      case ConversationType.groupChat:
        return 'Group Chat';
    }
  }

  /// Get display avatar for the conversation
  String? getDisplayAvatar(String currentUserId) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return avatarUrl;
    }

    if (type == ConversationType.directMessage &&
        participants != null &&
        participants!.isNotEmpty) {
      final otherParticipant = participants!.firstWhere(
          (p) => p.userId != currentUserId,
          orElse: () => participants!.first);
      return otherParticipant.avatarUrl;
    }

    return null;
  }

  /// Check if conversation is a direct message
  bool get isDirectMessage => type == ConversationType.directMessage;

  /// Check if conversation is a pulse group
  bool get isPulseGroup => type == ConversationType.pulseGroup;

  /// Check if conversation is a group chat
  bool get isGroupChat => type == ConversationType.groupChat;
}

/// Model class for conversation participants
@JsonSerializable()
class ConversationParticipant {
  final String id;
  final String conversationId;
  final String userId;
  final String role; // admin, moderator, member
  final DateTime joinedAt;
  final DateTime? lastReadAt;
  final bool isMuted;
  final Map<String, dynamic> notificationSettings;

  // User profile data (joined from profiles table)
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  const ConversationParticipant({
    required this.id,
    required this.conversationId,
    required this.userId,
    this.role = 'member',
    required this.joinedAt,
    this.lastReadAt,
    this.isMuted = false,
    this.notificationSettings = const {},
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  factory ConversationParticipant.fromJson(Map<String, dynamic> json) =>
      _$ConversationParticipantFromJson(json);

  Map<String, dynamic> toJson() => _$ConversationParticipantToJson(this);

  ConversationParticipant copyWith({
    String? id,
    String? conversationId,
    String? userId,
    String? role,
    DateTime? joinedAt,
    DateTime? lastReadAt,
    bool? isMuted,
    Map<String, dynamic>? notificationSettings,
    String? username,
    String? displayName,
    String? avatarUrl,
  }) {
    return ConversationParticipant(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      isMuted: isMuted ?? this.isMuted,
      notificationSettings: notificationSettings ?? this.notificationSettings,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  /// Check if participant is admin
  bool get isAdmin => role == 'admin';

  /// Check if participant is moderator
  bool get isModerator => role == 'moderator';

  /// Check if participant has admin or moderator privileges
  bool get hasModeratorPrivileges => isAdmin || isModerator;
}
