/// Model class for chat messages
class ChatMessage {
  final String id;
  final String pulseId;
  final String senderId;
  final String? senderName;
  final String? senderAvatarUrl;
  final String messageType;
  final String content;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime? expiresAt;

  ChatMessage({
    required this.id,
    required this.pulseId,
    required this.senderId,
    this.senderName,
    this.senderAvatarUrl,
    required this.messageType,
    required this.content,
    this.isDeleted = false,
    required this.createdAt,
    this.expiresAt,
  });

  /// Create a ChatMessage from JSON data
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      pulseId: json['pulse_id'],
      senderId: json['sender_id'],
      senderName: json['sender_name'],
      senderAvatarUrl: json['sender_avatar_url'],
      messageType: json['message_type'] ?? 'text',
      content: json['content'],
      isDeleted: json['is_deleted'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: json['expires_at'] != null 
          ? DateTime.parse(json['expires_at']) 
          : null,
    );
  }

  /// Convert ChatMessage to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pulse_id': pulseId,
      'sender_id': senderId,
      'message_type': messageType,
      'content': content,
      'is_deleted': isDeleted,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
    };
  }

  /// Check if the message is from the current user
  bool isFromCurrentUser(String currentUserId) {
    return senderId == currentUserId;
  }

  /// Check if the message is a system message
  bool get isSystemMessage => messageType == 'system';

  /// Check if the message is a location message
  bool get isLocationMessage => messageType == 'location';

  /// Check if the message is a text message
  bool get isTextMessage => messageType == 'text';

  /// Check if the message has expired
  bool isExpired() {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }
}
