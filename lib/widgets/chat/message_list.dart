import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/widgets/chat/message_widgets/message_bubble.dart';

/// Widget for displaying a list of messages with proper grouping and styling
class MessageList extends StatefulWidget {
  final List<Message> messages;
  final Conversation conversation;
  final ScrollController scrollController;
  final bool isLoadingMore;
  final bool hasMoreMessages;
  final String currentUserId;

  const MessageList({
    super.key,
    required this.messages,
    required this.conversation,
    required this.scrollController,
    required this.isLoadingMore,
    required this.hasMoreMessages,
    required this.currentUserId,
  });

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      ),
      child: ListView.builder(
        controller: widget.scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        itemCount: widget.messages.length + (widget.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          // Show loading indicator at the bottom when loading more messages
          if (index == widget.messages.length) {
            debugPrint(
                '🔄 PAGINATION DEBUG: Showing loading indicator at bottom - isLoadingMore=${widget.isLoadingMore}');
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          final message = widget.messages[index];
          final isFromCurrentUser = message.senderId == widget.currentUserId;

          // Determine message grouping
          final isFirstInGroup = _isFirstInGroup(index);
          final isLastInGroup = _isLastInGroup(index);

          // CRITICAL FIX: Create key that changes when message status changes
          // This ensures MessageBubble rebuilds when status updates occur
          final messageKey =
              ValueKey('${message.id}_${message.status.toString()}');

          return Padding(
            padding: EdgeInsets.only(
              top: isFirstInGroup ? 8 : 2,
              bottom: isLastInGroup ? 8 : 2,
            ),
            child: MessageBubble(
              key: messageKey,
              message: message,
              conversation: widget.conversation,
              isFromCurrentUser: isFromCurrentUser,
              isFirstInGroup: isFirstInGroup,
              isLastInGroup: isLastInGroup,
              onReply: (message) => _handleReply(message),
              onReact: (message, emoji) => _handleReaction(message, emoji),
              onDelete: (message) => _handleDelete(message),
              onForward: (message) => _handleForward(message),
              onLongPress: (message) => _showMessageOptions(message),
            ),
          );
        },
        reverse: false, // Keep normal ListView order
      ),
    );
  }

  /// Check if message is first in a group (same sender)
  bool _isFirstInGroup(int index) {
    if (index == 0) return true;

    final currentMessage = widget.messages[index];
    final previousMessage = widget.messages[index - 1];

    // Different sender
    if (currentMessage.senderId != previousMessage.senderId) return true;

    // More than 5 minutes apart
    final timeDiff =
        currentMessage.createdAt.difference(previousMessage.createdAt);
    if (timeDiff.inMinutes > 5) return true;

    // Different message type
    if (currentMessage.messageType != previousMessage.messageType) return true;

    return false;
  }

  /// Check if message is last in a group (same sender)
  bool _isLastInGroup(int index) {
    if (index == widget.messages.length - 1) return true;

    final currentMessage = widget.messages[index];
    final nextMessage = widget.messages[index + 1];

    // Different sender
    if (currentMessage.senderId != nextMessage.senderId) return true;

    // More than 5 minutes apart
    final timeDiff = nextMessage.createdAt.difference(currentMessage.createdAt);
    if (timeDiff.inMinutes > 5) return true;

    // Different message type
    if (currentMessage.messageType != nextMessage.messageType) return true;

    return false;
  }

  /// Handle reply to message
  void _handleReply(Message message) {
    // TODO: Implement reply functionality
    debugPrint('Reply to message: ${message.id}');
  }

  /// Handle message reaction
  void _handleReaction(Message message, String emoji) {
    // TODO: Implement reaction functionality
    debugPrint('React to message ${message.id} with $emoji');
  }

  /// Handle message deletion
  void _handleDelete(Message message) {
    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement delete functionality
              debugPrint('Delete message: ${message.id}');
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Handle message forwarding
  void _handleForward(Message message) {
    // TODO: Implement forward functionality
    debugPrint('Forward message: ${message.id}');
  }

  /// Show message options bottom sheet
  void _showMessageOptions(Message message) {
    final isFromCurrentUser = message.senderId == widget.currentUserId;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Reply option
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                _handleReply(message);
              },
            ),

            // Copy text option (for text messages)
            if (message.messageType == MessageType.text)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy Text'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Text copied to clipboard')),
                  );
                },
              ),

            // Forward option
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(context);
                _handleForward(message);
              },
            ),

            // Delete option (only for own messages)
            if (isFromCurrentUser)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title:
                    const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _handleDelete(message);
                },
              ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
