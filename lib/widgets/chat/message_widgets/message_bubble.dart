import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/widgets/chat/message_widgets/text_message_widget.dart';
import 'package:pulsemeet/widgets/chat/message_widgets/media_message_widget.dart';
import 'package:pulsemeet/widgets/chat/message_widgets/system_message_widget.dart';
import 'package:pulsemeet/widgets/chat/security_indicators.dart';
import 'package:pulsemeet/widgets/avatar.dart';

/// Main message bubble widget that adapts to different message types
class MessageBubble extends StatelessWidget {
  final Message message;
  final Conversation conversation;
  final bool isFromCurrentUser;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final Function(Message)? onReply;
  final Function(Message, String)? onReact;
  final Function(Message)? onDelete;
  final Function(Message)? onForward;
  final Function(Message)? onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.conversation,
    required this.isFromCurrentUser,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    this.onReply,
    this.onReact,
    this.onDelete,
    this.onForward,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // System messages have special styling
    if (message.messageType == MessageType.system) {
      return SystemMessageWidget(message: message);
    }

    return GestureDetector(
      onLongPress: () => onLongPress?.call(message),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: isFirstInGroup ? 4 : 1,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isFromCurrentUser) ...[
              // Avatar for other users (only show on last message in group)
              SizedBox(
                width: 32,
                child: isLastInGroup
                    ? UserAvatar(
                        userId: message.senderId,
                        avatarUrl: message.senderAvatarUrl,
                        size: 28,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
            ],

            // Message content
            Expanded(
              child: Column(
                crossAxisAlignment: isFromCurrentUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // Sender name (for group chats, first message in group)
                  if (!isFromCurrentUser &&
                      conversation.type != ConversationType.directMessage &&
                      isFirstInGroup)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 4),
                      child: Text(
                        message.senderName ?? 'Unknown',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _getSenderColor(message.senderId),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),

                  // Message bubble
                  _buildMessageBubble(context),

                  // Message status and time (only for last message in group)
                  if (isLastInGroup)
                    Padding(
                      padding: EdgeInsets.only(
                        left: isFromCurrentUser ? 0 : 12,
                        right: isFromCurrentUser ? 12 : 0,
                        top: 4,
                      ),
                      child: _buildMessageInfo(context),
                    ),
                ],
              ),
            ),

            if (isFromCurrentUser) ...[
              const SizedBox(width: 8),
              // Spacer for current user messages
              const SizedBox(width: 32),
            ],
          ],
        ),
      ),
    );
  }

  /// Build the main message bubble
  Widget _buildMessageBubble(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Determine bubble colors
    Color bubbleColor;
    Color textColor;

    if (isFromCurrentUser) {
      bubbleColor = theme.primaryColor;
      textColor = Colors.white;
    } else {
      bubbleColor = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E5EA);
      textColor = isDark ? Colors.white : Colors.black87;
    }

    // Determine border radius based on position in group
    BorderRadius borderRadius;
    if (isFromCurrentUser) {
      borderRadius = BorderRadius.only(
        topLeft: const Radius.circular(18),
        topRight: isFirstInGroup
            ? const Radius.circular(18)
            : const Radius.circular(4),
        bottomLeft: const Radius.circular(18),
        bottomRight: isLastInGroup
            ? const Radius.circular(4)
            : const Radius.circular(18),
      );
    } else {
      borderRadius = BorderRadius.only(
        topLeft: isFirstInGroup
            ? const Radius.circular(18)
            : const Radius.circular(4),
        topRight: const Radius.circular(18),
        bottomLeft: isLastInGroup
            ? const Radius.circular(4)
            : const Radius.circular(18),
        bottomRight: const Radius.circular(18),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reply-to message (if any)
          if (message.replyToMessage != null)
            _buildReplyPreview(context, textColor),

          // Main message content
          _buildMessageContent(context, textColor),

          // Message reactions (if any)
          if (message.hasReactions) _buildReactions(context),
        ],
      ),
    );
  }

  /// Build message content based on type
  Widget _buildMessageContent(BuildContext context, Color textColor) {
    switch (message.messageType) {
      case MessageType.text:
        return TextMessageWidget(
          message: message,
          textColor: textColor,
          isFromCurrentUser: isFromCurrentUser,
        );
      case MessageType.image:
      case MessageType.video:
      case MessageType.audio:
        return MediaMessageWidget(
          message: message,
          conversation: conversation,
          isFromCurrentUser: isFromCurrentUser,
        );
      default:
        return TextMessageWidget(
          message: message,
          textColor: textColor,
          isFromCurrentUser: isFromCurrentUser,
        );
    }
  }

  /// Build reply preview
  Widget _buildReplyPreview(BuildContext context, Color textColor) {
    final replyMessage = message.replyToMessage!;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: textColor.withOpacity(0.5),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            replyMessage.senderName ?? 'Unknown',
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor.withOpacity(0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            replyMessage.getDisplayContent(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: textColor.withOpacity(0.7),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Build message reactions
  Widget _buildReactions(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      child: Wrap(
        spacing: 4,
        children: message.reactions.map((reaction) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reaction.emoji,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 2),
                Text(
                  '1', // TODO: Count reactions by emoji
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Build message info (time and status)
  Widget _buildMessageInfo(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Message time
        Text(
          _formatMessageTime(message.createdAt),
          style: theme.textTheme.bodySmall?.copyWith(
            color: isDark ? Colors.grey[500] : Colors.grey[600],
            fontSize: 11,
          ),
        ),

        // Encryption indicator
        if (message.isEncrypted) ...[
          const SizedBox(width: 4),
          MessageEncryptionIndicator(
            isEncrypted: message.isEncrypted,
            isVerified: false, // TODO: Get verification status
            size: 10,
          ),
        ],

        // Message status (for current user messages)
        if (isFromCurrentUser) ...[
          const SizedBox(width: 4),
          _buildMessageStatus(context),
        ],
      ],
    );
  }

  /// Build message status indicator
  Widget _buildMessageStatus(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    IconData icon;
    Color color = isDark ? Colors.grey[500]! : Colors.grey[600]!;

    switch (message.status) {
      case MessageStatus.sending:
        icon = Icons.access_time;
        break;
      case MessageStatus.sent:
        icon = Icons.check;
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        break;
      case MessageStatus.read:
        icon = Icons.done_all;
        color = theme.primaryColor;
        break;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        color = Colors.red;
        break;
    }

    return Icon(
      icon,
      size: 12,
      color: color,
    );
  }

  /// Get sender color for group chats
  Color _getSenderColor(String senderId) {
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
    ];

    final hash = senderId.hashCode;
    return colors[hash.abs() % colors.length];
  }

  /// Format message time
  String _formatMessageTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays == 0) {
      // Today - show time
      final hour = time.hour;
      final minute = time.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    } else {
      // Other days - show relative time
      return timeago.format(time, allowFromNow: true);
    }
  }
}
