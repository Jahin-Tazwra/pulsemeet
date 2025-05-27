// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Conversation _$ConversationFromJson(Map<String, dynamic> json) => Conversation(
      id: json['id'] as String,
      type: $enumDecode(_$ConversationTypeEnumMap, json['type']),
      title: json['title'] as String?,
      description: json['description'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      pulseId: json['pulse_id'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lastMessageAt: json['last_message_at'] == null
          ? null
          : DateTime.parse(json['last_message_at'] as String),
      isArchived: json['is_archived'] as bool? ?? false,
      isMuted: json['is_muted'] as bool? ?? false,
      settings: json['settings'] as Map<String, dynamic>? ?? const {},
      encryptionEnabled: json['encryption_enabled'] as bool? ?? true,
      encryptionKeyId: json['encryption_key_id'] as String?,
      unreadCount: (json['unreadCount'] as num?)?.toInt(),
      lastMessagePreview: json['lastMessagePreview'] as String?,
      participants: (json['participants'] as List<dynamic>?)
          ?.map((e) =>
              ConversationParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ConversationToJson(Conversation instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': _$ConversationTypeEnumMap[instance.type]!,
      'title': instance.title,
      'description': instance.description,
      'avatar_url': instance.avatarUrl,
      'pulse_id': instance.pulseId,
      'created_by': instance.createdBy,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'last_message_at': instance.lastMessageAt?.toIso8601String(),
      'is_archived': instance.isArchived,
      'is_muted': instance.isMuted,
      'settings': instance.settings,
      'encryption_enabled': instance.encryptionEnabled,
      'encryption_key_id': instance.encryptionKeyId,
      'unreadCount': instance.unreadCount,
      'lastMessagePreview': instance.lastMessagePreview,
      'participants': instance.participants,
    };

const _$ConversationTypeEnumMap = {
  ConversationType.pulseGroup: 'pulse_group',
  ConversationType.directMessage: 'direct_message',
  ConversationType.groupChat: 'group_chat',
};

ConversationParticipant _$ConversationParticipantFromJson(
        Map<String, dynamic> json) =>
    ConversationParticipant(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      userId: json['userId'] as String,
      role: json['role'] as String? ?? 'member',
      joinedAt: DateTime.parse(json['joinedAt'] as String),
      lastReadAt: json['lastReadAt'] == null
          ? null
          : DateTime.parse(json['lastReadAt'] as String),
      isMuted: json['isMuted'] as bool? ?? false,
      notificationSettings:
          json['notificationSettings'] as Map<String, dynamic>? ?? const {},
      username: json['username'] as String?,
      displayName: json['displayName'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );

Map<String, dynamic> _$ConversationParticipantToJson(
        ConversationParticipant instance) =>
    <String, dynamic>{
      'id': instance.id,
      'conversationId': instance.conversationId,
      'userId': instance.userId,
      'role': instance.role,
      'joinedAt': instance.joinedAt.toIso8601String(),
      'lastReadAt': instance.lastReadAt?.toIso8601String(),
      'isMuted': instance.isMuted,
      'notificationSettings': instance.notificationSettings,
      'username': instance.username,
      'displayName': instance.displayName,
      'avatarUrl': instance.avatarUrl,
    };
