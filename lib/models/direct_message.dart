import 'dart:convert';
import 'package:pulsemeet/models/chat_message.dart';
import 'package:pulsemeet/models/formatted_text.dart';
import 'package:uuid/uuid.dart';

/// Model class for direct messages between users
class DirectMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String? senderName;
  final String? senderAvatarUrl;
  final String messageType;
  final String content;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final MessageStatus status;
  final bool isFormatted;
  final MediaData? mediaData;
  final LocationData? locationData;
  final String? replyToId;
  final DateTime? editedAt;
  final bool isOffline;

  DirectMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.senderName,
    this.senderAvatarUrl,
    required this.messageType,
    required this.content,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
    this.status = MessageStatus.sent,
    this.isFormatted = false,
    this.mediaData,
    this.locationData,
    this.replyToId,
    this.editedAt,
    this.isOffline = false,
  });

  /// Create DirectMessage from JSON
  factory DirectMessage.fromJson(Map<String, dynamic> json) {
    // Parse reactions if available
    List<MessageReaction> reactions = [];
    if (json['reactions'] != null) {
      try {
        final reactionsData = json['reactions'] is String
            ? jsonDecode(json['reactions'])
            : json['reactions'];
        if (reactionsData is List) {
          reactions = reactionsData
              .map<MessageReaction>((r) => MessageReaction.fromJson(r))
              .toList();
        }
      } catch (e) {
        // Ignore parsing errors
      }
    }

    // Parse media data if available
    MediaData? mediaData;
    if (json['media_data'] != null) {
      try {
        final mediaDataJson = json['media_data'] is String
            ? jsonDecode(json['media_data'])
            : json['media_data'];
        mediaData = MediaData.fromJson(mediaDataJson);
      } catch (e) {
        // Ignore parsing errors
      }
    }

    // Parse location data if available
    LocationData? locationData;
    if (json['location_data'] != null) {
      try {
        final locationDataJson = json['location_data'] is String
            ? jsonDecode(json['location_data'])
            : json['location_data'];
        locationData = LocationData.fromJson(locationDataJson);
      } catch (e) {
        // Ignore parsing errors
      }
    }

    return DirectMessage(
      id: json['id'],
      senderId: json['sender_id'],
      receiverId: json['receiver_id'],
      senderName: json['sender_name'],
      senderAvatarUrl: json['sender_avatar_url'],
      messageType: json['message_type'] ?? 'text',
      content: json['content'],
      isDeleted: json['is_deleted'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      status: _parseMessageStatus(json['status']),
      isFormatted: json['is_formatted'] ?? false,
      mediaData: mediaData,
      locationData: locationData,
      replyToId: json['reply_to_id'],
      editedAt:
          json['edited_at'] != null ? DateTime.parse(json['edited_at']) : null,
      isOffline: json['is_offline'] ?? false,
    );
  }

  /// Convert DirectMessage to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message_type': messageType,
      'content': content,
      'is_deleted': isDeleted,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'status': status.toString().split('.').last,
      'is_formatted': isFormatted,
      'media_data': mediaData != null ? jsonEncode(mediaData!.toJson()) : null,
      'location_data':
          locationData != null ? jsonEncode(locationData!.toJson()) : null,
      'reply_to_id': replyToId,
      'edited_at': editedAt?.toIso8601String(),
    };
  }

  /// Create a copy of DirectMessage with updated fields
  DirectMessage copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? senderName,
    String? senderAvatarUrl,
    String? messageType,
    String? content,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
    MessageStatus? status,
    bool? isFormatted,
    MediaData? mediaData,
    LocationData? locationData,
    String? replyToId,
    DateTime? editedAt,
    bool? isOffline,
  }) {
    return DirectMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      senderName: senderName ?? this.senderName,
      senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      isFormatted: isFormatted ?? this.isFormatted,
      mediaData: mediaData ?? this.mediaData,
      locationData: locationData ?? this.locationData,
      replyToId: replyToId ?? this.replyToId,
      editedAt: editedAt ?? this.editedAt,
      isOffline: isOffline ?? this.isOffline,
    );
  }

  /// Get formatted text if the message is formatted
  FormattedText? getFormattedText() {
    if (!isFormatted) return null;
    try {
      return FormattedText.decode(content);
    } catch (e) {
      return null;
    }
  }

  /// Check if the message is from the current user
  bool isFromCurrentUser(String currentUserId) {
    return senderId == currentUserId;
  }

  /// Check if the message is a text message
  bool get isTextMessage => messageType == 'text';

  /// Check if the message is an image message
  bool get isImageMessage => messageType == 'image';

  /// Check if the message is a video message
  bool get isVideoMessage => messageType == 'video';

  /// Check if the message is an audio message
  bool get isAudioMessage => messageType == 'audio';

  /// Check if the message is a location message
  bool get isLocationMessage => messageType == 'location';

  /// Check if the message is a live location message
  bool get isLiveLocationMessage => messageType == 'liveLocation';

  /// Check if the message is a system message
  bool get isSystemMessage => messageType == 'system';

  /// Parse message status from string
  static MessageStatus _parseMessageStatus(String? status) {
    if (status == null) return MessageStatus.sent;
    
    switch (status) {
      case 'sending':
        return MessageStatus.sending;
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      case 'failed':
        return MessageStatus.failed;
      default:
        return MessageStatus.sent;
    }
  }

  /// Create a message for offline queue
  factory DirectMessage.offline({
    required String senderId,
    required String receiverId,
    required String messageType,
    required String content,
    MediaData? mediaData,
    LocationData? locationData,
    bool isFormatted = false,
    String? replyToId,
  }) {
    final now = DateTime.now();
    return DirectMessage(
      id: const Uuid().v4(),
      senderId: senderId,
      receiverId: receiverId,
      messageType: messageType,
      content: content,
      createdAt: now,
      updatedAt: now,
      status: MessageStatus.sending,
      isFormatted: isFormatted,
      mediaData: mediaData,
      locationData: locationData,
      replyToId: replyToId,
      isOffline: true,
    );
  }
}
