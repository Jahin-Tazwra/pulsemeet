import 'package:json_annotation/json_annotation.dart';

part 'message.g.dart';

/// Enum for message types
enum MessageType {
  @JsonValue('text')
  text,
  @JsonValue('image')
  image,
  @JsonValue('video')
  video,
  @JsonValue('audio')
  audio,
  @JsonValue('file')
  file,
  @JsonValue('location')
  location,
  @JsonValue('system')
  system,
  @JsonValue('call')
  call,
}

/// Enum for message status
enum MessageStatus {
  @JsonValue('sending')
  sending,
  @JsonValue('sent')
  sent,
  @JsonValue('delivered')
  delivered,
  @JsonValue('read')
  read,
  @JsonValue('failed')
  failed,
}

/// Model class for messages (unified for all conversation types)
@JsonSerializable()
class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final MessageType messageType;
  final String content;
  final bool isDeleted;
  final bool isEdited;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? editedAt;
  final DateTime? expiresAt;
  final MessageStatus status;
  final String? replyToId;
  final String? forwardFromId;
  final List<MessageReaction> reactions;
  final List<String> mentions;
  final MediaData? mediaData;
  final LocationData? locationData;
  final CallData? callData;
  final bool isFormatted;
  final bool isEncrypted;
  final Map<String, dynamic>? encryptionMetadata;
  final int keyVersion;
  
  // Runtime properties (not stored in DB)
  final String? senderName;
  final String? senderAvatarUrl;
  final Message? replyToMessage;
  final bool isOffline;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.messageType,
    required this.content,
    this.isDeleted = false,
    this.isEdited = false,
    required this.createdAt,
    required this.updatedAt,
    this.editedAt,
    this.expiresAt,
    this.status = MessageStatus.sent,
    this.replyToId,
    this.forwardFromId,
    this.reactions = const [],
    this.mentions = const [],
    this.mediaData,
    this.locationData,
    this.callData,
    this.isFormatted = false,
    this.isEncrypted = false,
    this.encryptionMetadata,
    this.keyVersion = 1,
    this.senderName,
    this.senderAvatarUrl,
    this.replyToMessage,
    this.isOffline = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) => _$MessageFromJson(json);

  Map<String, dynamic> toJson() => _$MessageToJson(this);

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    MessageType? messageType,
    String? content,
    bool? isDeleted,
    bool? isEdited,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? editedAt,
    DateTime? expiresAt,
    MessageStatus? status,
    String? replyToId,
    String? forwardFromId,
    List<MessageReaction>? reactions,
    List<String>? mentions,
    MediaData? mediaData,
    LocationData? locationData,
    CallData? callData,
    bool? isFormatted,
    bool? isEncrypted,
    Map<String, dynamic>? encryptionMetadata,
    int? keyVersion,
    String? senderName,
    String? senderAvatarUrl,
    Message? replyToMessage,
    bool? isOffline,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      isDeleted: isDeleted ?? this.isDeleted,
      isEdited: isEdited ?? this.isEdited,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      editedAt: editedAt ?? this.editedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
      replyToId: replyToId ?? this.replyToId,
      forwardFromId: forwardFromId ?? this.forwardFromId,
      reactions: reactions ?? this.reactions,
      mentions: mentions ?? this.mentions,
      mediaData: mediaData ?? this.mediaData,
      locationData: locationData ?? this.locationData,
      callData: callData ?? this.callData,
      isFormatted: isFormatted ?? this.isFormatted,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      encryptionMetadata: encryptionMetadata ?? this.encryptionMetadata,
      keyVersion: keyVersion ?? this.keyVersion,
      senderName: senderName ?? this.senderName,
      senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
      replyToMessage: replyToMessage ?? this.replyToMessage,
      isOffline: isOffline ?? this.isOffline,
    );
  }

  /// Check if message is from current user
  bool isFromCurrentUser(String currentUserId) => senderId == currentUserId;

  /// Check if message has media
  bool get hasMedia => mediaData != null;

  /// Check if message has location
  bool get hasLocation => locationData != null;

  /// Check if message is a reply
  bool get isReply => replyToId != null;

  /// Check if message is forwarded
  bool get isForwarded => forwardFromId != null;

  /// Check if message has reactions
  bool get hasReactions => reactions.isNotEmpty;

  /// Check if message mentions current user
  bool mentionsUser(String userId) => mentions.contains(userId);

  /// Get display content (handles deleted messages, etc.)
  String getDisplayContent() {
    if (isDeleted) {
      return 'This message was deleted';
    }
    
    if (messageType == MessageType.system) {
      return content;
    }
    
    if (hasMedia && content.isEmpty) {
      switch (messageType) {
        case MessageType.image:
          return '📷 Photo';
        case MessageType.video:
          return '🎥 Video';
        case MessageType.audio:
          return '🎵 Audio';
        case MessageType.file:
          return '📎 File';
        default:
          return content;
      }
    }
    
    return content;
  }

  /// Create a system message
  factory Message.system({
    required String conversationId,
    required String content,
    String? senderId,
  }) {
    return Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: conversationId,
      senderId: senderId ?? 'system',
      messageType: MessageType.system,
      content: content,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      status: MessageStatus.sent,
    );
  }

  /// Create an offline message
  factory Message.offline({
    required String conversationId,
    required String senderId,
    required MessageType messageType,
    required String content,
    MediaData? mediaData,
    LocationData? locationData,
    bool isFormatted = false,
    String? replyToId,
  }) {
    return Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: conversationId,
      senderId: senderId,
      messageType: messageType,
      content: content,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      status: MessageStatus.sending,
      isFormatted: isFormatted,
      mediaData: mediaData,
      locationData: locationData,
      replyToId: replyToId,
      isOffline: true,
      isEncrypted: false, // Offline messages start unencrypted
      keyVersion: 1,
    );
  }
}

/// Model class for message reactions
@JsonSerializable()
class MessageReaction {
  final String userId;
  final String emoji;
  final DateTime createdAt;
  
  // User profile data (joined from profiles table)
  final String? username;
  final String? displayName;

  const MessageReaction({
    required this.userId,
    required this.emoji,
    required this.createdAt,
    this.username,
    this.displayName,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) =>
      _$MessageReactionFromJson(json);

  Map<String, dynamic> toJson() => _$MessageReactionToJson(this);
}

/// Model class for media data
@JsonSerializable()
class MediaData {
  final String url;
  final String? thumbnailUrl;
  final String mimeType;
  final int size;
  final int? width;
  final int? height;
  final int? duration; // For audio/video in seconds
  final String? fileName;
  final bool isEncrypted;

  const MediaData({
    required this.url,
    this.thumbnailUrl,
    required this.mimeType,
    required this.size,
    this.width,
    this.height,
    this.duration,
    this.fileName,
    this.isEncrypted = false,
  });

  factory MediaData.fromJson(Map<String, dynamic> json) =>
      _$MediaDataFromJson(json);

  Map<String, dynamic> toJson() => _$MediaDataToJson(this);

  /// Check if media is an image
  bool get isImage => mimeType.startsWith('image/');

  /// Check if media is a video
  bool get isVideo => mimeType.startsWith('video/');

  /// Check if media is audio
  bool get isAudio => mimeType.startsWith('audio/');

  /// Get formatted file size
  String get formattedSize {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}

/// Model class for location data
@JsonSerializable()
class LocationData {
  final double latitude;
  final double longitude;
  final String? address;
  final String? name;
  final bool isLiveLocation;
  final DateTime? liveLocationExpiresAt;

  const LocationData({
    required this.latitude,
    required this.longitude,
    this.address,
    this.name,
    this.isLiveLocation = false,
    this.liveLocationExpiresAt,
  });

  factory LocationData.fromJson(Map<String, dynamic> json) =>
      _$LocationDataFromJson(json);

  Map<String, dynamic> toJson() => _$LocationDataToJson(this);
}

/// Model class for call data
@JsonSerializable()
class CallData {
  final String callId;
  final String callType; // voice, video
  final int duration; // in seconds
  final String status; // missed, answered, declined
  final List<String> participants;

  const CallData({
    required this.callId,
    required this.callType,
    required this.duration,
    required this.status,
    required this.participants,
  });

  factory CallData.fromJson(Map<String, dynamic> json) =>
      _$CallDataFromJson(json);

  Map<String, dynamic> toJson() => _$CallDataToJson(this);

  /// Check if call was missed
  bool get isMissed => status == 'missed';

  /// Check if call was answered
  bool get wasAnswered => status == 'answered';

  /// Get formatted duration
  String get formattedDuration {
    if (duration < 60) return '${duration}s';
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}
