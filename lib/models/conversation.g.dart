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
      avatarUrl: json['avatarUrl'] as String?,
      pulseId: json['pulseId'] as String?,
      createdBy: json['createdBy'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      lastMessageAt: json['lastMessageAt'] == null
          ? null
          : DateTime.parse(json['lastMessageAt'] as String),
      isArchived: json['isArchived'] as bool? ?? false,
      isMuted: json['isMuted'] as bool? ?? false,
      settings: json['settings'] as Map<String, dynamic>? ?? const {},
      encryptionEnabled: json['encryptionEnabled'] as bool? ?? true,
      encryptionKeyId: json['encryptionKeyId'] as String?,
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
      'avatarUrl': instance.avatarUrl,
      'pulseId': instance.pulseId,
      'createdBy': instance.createdBy,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'lastMessageAt': instance.lastMessageAt?.toIso8601String(),
      'isArchived': instance.isArchived,
      'isMuted': instance.isMuted,
      'settings': instance.settings,
      'encryptionEnabled': instance.encryptionEnabled,
      'encryptionKeyId': instance.encryptionKeyId,
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
