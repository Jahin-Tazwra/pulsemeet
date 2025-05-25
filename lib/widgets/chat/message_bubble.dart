import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/models/encryption_key.dart';
import 'package:pulsemeet/widgets/chat/message_content.dart';
import 'package:pulsemeet/widgets/chat/message_reactions.dart';
import 'package:pulsemeet/widgets/chat/message_status_indicator.dart';
import 'package:pulsemeet/widgets/encryption_indicator.dart';

/// A widget that displays a chat message bubble
class MessageBubble extends StatelessWidget {
  final Message message;
  final Message? previousMessage;
  final Message? nextMessage;
  final String currentUserId;
  final Function(String) onReactionTap;
  final Function(Message) onMessageTap;
  final Function(Message) onMessageLongPress;
  final Function(Message)? onReplyTap;
  final Message? replyToMessage;
  final String? conversationId;
  final ConversationType? conversationType;

  const MessageBubble({
    super.key,
    required this.message,
    this.previousMessage,
    this.nextMessage,
    required this.currentUserId,
    required this.onReactionTap,
    required this.onMessageTap,
    required this.onMessageLongPress,
    this.onReplyTap,
    this.replyToMessage,
    this.conversationId,
    this.conversationType,
  });

  @override
  Widget build(BuildContext context) {
    // Determine if the message is from the current user
    // This is the critical part that determines message alignment
    final bool isFromCurrentUser = message.isFromCurrentUser(currentUserId);

    // For debugging purposes, print the message content and its alignment
    debugPrint(
        'Message: "${message.content.substring(0, message.content.length > 20 ? 20 : message.content.length)}..." - isFromCurrentUser: $isFromCurrentUser');

    final bool isSystemMessage = message.messageType == MessageType.system;

    // Format timestamp
    final String timeString = _formatTime(message.createdAt);

    // System messages have a different style
    if (isSystemMessage) {
      return _buildSystemMessage(context, timeString);
    }

    return Column(
      crossAxisAlignment:
          isFromCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // Show sender name for all messages from other users
        if (!isFromCurrentUser && message.senderName != null)
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 8.0),
            child: Text(
              message.senderName!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),

        // Reply indicator if this is a reply
        if (message.replyToId != null && replyToMessage != null)
          _buildReplyIndicator(context, replyToMessage!),

        // Main message bubble
        GestureDetector(
          onTap: () => onMessageTap(message),
          onLongPress: () => onMessageLongPress(message),
          child: Align(
            alignment: isFromCurrentUser
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width *
                    0.65, // Max width as 65% of screen width
                minWidth: 60.0, // Minimum width for very short messages
              ),
              child: Container(
                margin: EdgeInsets.only(
                  top: 4.0,
                  bottom: 4.0,
                  left: isFromCurrentUser ? 0.0 : 12.0,
                  right: isFromCurrentUser ? 12.0 : 0.0,
                ),
                decoration: BoxDecoration(
                  color: isFromCurrentUser
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                  borderRadius: _getBubbleRadius(isFromCurrentUser),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(15),
                      blurRadius: 1.5,
                      offset: const Offset(0, 1),
                    ),
                  ],
                  border: !isFromCurrentUser
                      ? Border.all(
                          color: Colors.grey.withAlpha(30),
                          width: 0.5,
                        )
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: _getBubbleRadius(isFromCurrentUser),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Message content
                      MessageContent(
                        message: message,
                        isFromCurrentUser: isFromCurrentUser,
                        conversationId: conversationId,
                        conversationType: conversationType,
                      ),

                      // Timestamp and status
                      Padding(
                        padding: const EdgeInsets.only(
                          right: 8.0,
                          bottom: 4.0,
                          left: 8.0,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: isFromCurrentUser
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: [
                            Text(
                              timeString,
                              style: TextStyle(
                                fontSize: 10,
                                color: isFromCurrentUser
                                    ? Colors.white.withAlpha(179) // 0.7 opacity
                                    : Colors.black54,
                              ),
                            ),
                            // Encryption badge
                            MessageEncryptionBadge(
                              isEncrypted: message.isEncrypted,
                              isDecryptionFailed: message.content.contains(
                                  '[Encrypted message - decryption failed]'),
                            ),
                            if (isFromCurrentUser)
                              Padding(
                                padding: const EdgeInsets.only(left: 4.0),
                                child: MessageStatusIndicator(
                                  status: message.status,
                                  // Make the indicator more visible for sending status
                                  size: message.status == MessageStatus.sending
                                      ? 14.0
                                      : 12.0,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Reactions
        if (message.reactions.isNotEmpty)
          Align(
            alignment: isFromCurrentUser
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(
                left: isFromCurrentUser ? 0.0 : 16.0,
                right: isFromCurrentUser ? 16.0 : 0.0,
                bottom: 4.0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.65,
                  minWidth: 60.0,
                ),
                child: MessageReactions(
                  reactions: message.reactions,
                  onReactionTap: () => onReactionTap(message.id),
                  alignment: isFromCurrentUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Build a system message
  Widget _buildSystemMessage(BuildContext context, String timeString) {
    return Container(
      margin: const EdgeInsets.symmetric(
        vertical: 12.0,
        horizontal: 64.0,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 8.0,
            horizontal: 16.0,
          ),
          decoration: BoxDecoration(
            color: Colors.grey.withAlpha(50),
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Column(
            children: [
              Text(
                message.content,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                timeString,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a reply indicator
  Widget _buildReplyIndicator(BuildContext context, Message replyToMessage) {
    final bool isFromCurrentUser = message.isFromCurrentUser(currentUserId);

    return GestureDetector(
      onTap: () => onReplyTap?.call(replyToMessage),
      child: Align(
        alignment:
            isFromCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.65,
            minWidth: 60.0,
          ),
          child: Container(
            margin: EdgeInsets.only(
              top: 4.0,
              left: isFromCurrentUser ? 0.0 : 16.0,
              right: isFromCurrentUser ? 16.0 : 0.0,
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 4.0,
              horizontal: 8.0,
            ),
            decoration: BoxDecoration(
              color: isFromCurrentUser
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withAlpha(77) // 0.3 opacity
                  : Theme.of(context)
                      .colorScheme
                      .surface
                      .withAlpha(179), // 0.7 opacity
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(
                color: isFromCurrentUser
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withAlpha(128) // 0.5 opacity
                    : Colors.grey.withAlpha(77), // 0.3 opacity
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.reply,
                  size: 12,
                  color: isFromCurrentUser
                      ? Theme.of(context).colorScheme.onPrimary
                      : Colors.grey,
                ),
                const SizedBox(width: 4.0),
                Flexible(
                  child: Text(
                    replyToMessage.isDeleted
                        ? 'This message was deleted'
                        : _getReplyPreview(replyToMessage),
                    style: TextStyle(
                      fontSize: 12,
                      color: isFromCurrentUser
                          ? Theme.of(context).colorScheme.onPrimary
                          : Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Get a preview of the reply message content
  String _getReplyPreview(Message message) {
    switch (message.messageType) {
      case MessageType.text:
        return message.content;
      case MessageType.image:
        return '📷 Photo';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.audio:
        return '🎵 Audio';
      case MessageType.location:
        return '📍 Location';
      case MessageType.file:
        return '📎 File';
      case MessageType.call:
        return '📞 Call';
      default:
        return 'Message';
    }
  }

  /// Format the timestamp
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return DateFormat('h:mm a').format(dateTime);
    } else if (messageDate == yesterday) {
      return 'Yesterday, ${DateFormat('h:mm a').format(dateTime)}';
    } else {
      return DateFormat('MMM d, h:mm a').format(dateTime);
    }
  }

  // We now always show sender info for messages from other users

  /// Get the appropriate bubble radius based on message grouping
  BorderRadius _getBubbleRadius(bool isFromCurrentUser) {
    const double radius = 18.0;
    const double smallRadius = 4.0;

    // Check if this message is part of a group
    // We need to ensure consistent grouping based on the sender
    final bool isFirstInGroup = previousMessage == null ||
        previousMessage!.isFromCurrentUser(currentUserId) !=
            isFromCurrentUser ||
        previousMessage!.senderId != message.senderId ||
        message.createdAt.difference(previousMessage!.createdAt).inMinutes > 2;

    final bool isLastInGroup = nextMessage == null ||
        nextMessage!.isFromCurrentUser(currentUserId) != isFromCurrentUser ||
        nextMessage!.senderId != message.senderId ||
        nextMessage!.createdAt.difference(message.createdAt).inMinutes > 2;

    if (isFromCurrentUser) {
      // Current user's messages (right side)
      if (isFirstInGroup && isLastInGroup) {
        // Single message
        return BorderRadius.circular(radius);
      } else if (isFirstInGroup) {
        // First message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(smallRadius),
        );
      } else if (isLastInGroup) {
        // Last message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(smallRadius),
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
        );
      } else {
        // Middle message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(smallRadius),
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(smallRadius),
        );
      }
    } else {
      // Other user's messages (left side)
      if (isFirstInGroup && isLastInGroup) {
        // Single message
        return BorderRadius.circular(radius);
      } else if (isFirstInGroup) {
        // First message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
          bottomLeft: Radius.circular(smallRadius),
          bottomRight: Radius.circular(radius),
        );
      } else if (isLastInGroup) {
        // Last message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(smallRadius),
          topRight: Radius.circular(radius),
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
        );
      } else {
        // Middle message in group
        return const BorderRadius.only(
          topLeft: Radius.circular(smallRadius),
          topRight: Radius.circular(radius),
          bottomLeft: Radius.circular(smallRadius),
          bottomRight: Radius.circular(radius),
        );
      }
    }
  }
}
