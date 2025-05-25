// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Message _$MessageFromJson(Map<String, dynamic> json) => Message(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      senderId: json['senderId'] as String,
      messageType: $enumDecode(_$MessageTypeEnumMap, json['messageType']),
      content: json['content'] as String,
      isDeleted: json['isDeleted'] as bool? ?? false,
      isEdited: json['isEdited'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      editedAt: json['editedAt'] == null
          ? null
          : DateTime.parse(json['editedAt'] as String),
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt'] as String),
      status: $enumDecodeNullable(_$MessageStatusEnumMap, json['status']) ??
          MessageStatus.sent,
      replyToId: json['replyToId'] as String?,
      forwardFromId: json['forwardFromId'] as String?,
      reactions: (json['reactions'] as List<dynamic>?)
              ?.map((e) => MessageReaction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      mentions: (json['mentions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      mediaData: json['mediaData'] == null
          ? null
          : MediaData.fromJson(json['mediaData'] as Map<String, dynamic>),
      locationData: json['locationData'] == null
          ? null
          : LocationData.fromJson(json['locationData'] as Map<String, dynamic>),
      callData: json['callData'] == null
          ? null
          : CallData.fromJson(json['callData'] as Map<String, dynamic>),
      isFormatted: json['isFormatted'] as bool? ?? false,
      isEncrypted: json['isEncrypted'] as bool? ?? false,
      encryptionMetadata: json['encryptionMetadata'] as Map<String, dynamic>?,
      keyVersion: (json['keyVersion'] as num?)?.toInt() ?? 1,
      senderName: json['senderName'] as String?,
      senderAvatarUrl: json['senderAvatarUrl'] as String?,
      replyToMessage: json['replyToMessage'] == null
          ? null
          : Message.fromJson(json['replyToMessage'] as Map<String, dynamic>),
      isOffline: json['isOffline'] as bool? ?? false,
    );

Map<String, dynamic> _$MessageToJson(Message instance) => <String, dynamic>{
      'id': instance.id,
      'conversationId': instance.conversationId,
      'senderId': instance.senderId,
      'messageType': _$MessageTypeEnumMap[instance.messageType]!,
      'content': instance.content,
      'isDeleted': instance.isDeleted,
      'isEdited': instance.isEdited,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'editedAt': instance.editedAt?.toIso8601String(),
      'expiresAt': instance.expiresAt?.toIso8601String(),
      'status': _$MessageStatusEnumMap[instance.status]!,
      'replyToId': instance.replyToId,
      'forwardFromId': instance.forwardFromId,
      'reactions': instance.reactions,
      'mentions': instance.mentions,
      'mediaData': instance.mediaData,
      'locationData': instance.locationData,
      'callData': instance.callData,
      'isFormatted': instance.isFormatted,
      'isEncrypted': instance.isEncrypted,
      'encryptionMetadata': instance.encryptionMetadata,
      'keyVersion': instance.keyVersion,
      'senderName': instance.senderName,
      'senderAvatarUrl': instance.senderAvatarUrl,
      'replyToMessage': instance.replyToMessage,
      'isOffline': instance.isOffline,
    };

const _$MessageTypeEnumMap = {
  MessageType.text: 'text',
  MessageType.image: 'image',
  MessageType.video: 'video',
  MessageType.audio: 'audio',
  MessageType.file: 'file',
  MessageType.location: 'location',
  MessageType.system: 'system',
  MessageType.call: 'call',
};

const _$MessageStatusEnumMap = {
  MessageStatus.sending: 'sending',
  MessageStatus.sent: 'sent',
  MessageStatus.delivered: 'delivered',
  MessageStatus.read: 'read',
  MessageStatus.failed: 'failed',
};

MessageReaction _$MessageReactionFromJson(Map<String, dynamic> json) =>
    MessageReaction(
      userId: json['userId'] as String,
      emoji: json['emoji'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      username: json['username'] as String?,
      displayName: json['displayName'] as String?,
    );

Map<String, dynamic> _$MessageReactionToJson(MessageReaction instance) =>
    <String, dynamic>{
      'userId': instance.userId,
      'emoji': instance.emoji,
      'createdAt': instance.createdAt.toIso8601String(),
      'username': instance.username,
      'displayName': instance.displayName,
    };

MediaData _$MediaDataFromJson(Map<String, dynamic> json) => MediaData(
      url: json['url'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      mimeType: json['mimeType'] as String,
      size: (json['size'] as num).toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      duration: (json['duration'] as num?)?.toInt(),
      fileName: json['fileName'] as String?,
      isEncrypted: json['isEncrypted'] as bool? ?? false,
    );

Map<String, dynamic> _$MediaDataToJson(MediaData instance) => <String, dynamic>{
      'url': instance.url,
      'thumbnailUrl': instance.thumbnailUrl,
      'mimeType': instance.mimeType,
      'size': instance.size,
      'width': instance.width,
      'height': instance.height,
      'duration': instance.duration,
      'fileName': instance.fileName,
      'isEncrypted': instance.isEncrypted,
    };

LocationData _$LocationDataFromJson(Map<String, dynamic> json) => LocationData(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String?,
      name: json['name'] as String?,
      isLiveLocation: json['isLiveLocation'] as bool? ?? false,
      liveLocationExpiresAt: json['liveLocationExpiresAt'] == null
          ? null
          : DateTime.parse(json['liveLocationExpiresAt'] as String),
    );

Map<String, dynamic> _$LocationDataToJson(LocationData instance) =>
    <String, dynamic>{
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'address': instance.address,
      'name': instance.name,
      'isLiveLocation': instance.isLiveLocation,
      'liveLocationExpiresAt':
          instance.liveLocationExpiresAt?.toIso8601String(),
    };

CallData _$CallDataFromJson(Map<String, dynamic> json) => CallData(
      callId: json['callId'] as String,
      callType: json['callType'] as String,
      duration: (json['duration'] as num).toInt(),
      status: json['status'] as String,
      participants: (json['participants'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$CallDataToJson(CallData instance) => <String, dynamic>{
      'callId': instance.callId,
      'callType': instance.callType,
      'duration': instance.duration,
      'status': instance.status,
      'participants': instance.participants,
    };
