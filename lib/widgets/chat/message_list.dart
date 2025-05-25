import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/widgets/chat/message_widgets/message_bubble.dart';
import 'package:pulsemeet/widgets/chat/message_widgets/date_separator.dart';
import 'package:pulsemeet/widgets/common/loading_indicator.dart';

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
  final Map<String, GlobalKey> _messageKeys = {};

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
        itemCount: _getItemCount(),
        itemBuilder: (context, index) => _buildItem(context, index),
        reverse: false, // Messages are ordered chronologically
      ),
    );
  }

  /// Get total item count including loading indicator and date separators
  int _getItemCount() {
    int count = 0;
    
    // Loading more indicator at top
    if (widget.isLoadingMore) count++;
    
    // Messages with date separators
    for (int i = 0; i < widget.messages.length; i++) {
      // Add date separator if needed
      if (_shouldShowDateSeparator(i)) count++;
      
      // Add message
      count++;
    }
    
    return count;
  }

  /// Build item at index
  Widget _buildItem(BuildContext context, int index) {
    int currentIndex = index;
    
    // Loading more indicator at top
    if (widget.isLoadingMore) {
      if (currentIndex == 0) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: LoadingIndicator()),
        );
      }
      currentIndex--;
    }
    
    // Find the actual message index accounting for date separators
    int messageIndex = 0;
    int itemsSeen = 0;
    
    for (int i = 0; i < widget.messages.length; i++) {
      // Check if we need a date separator
      if (_shouldShowDateSeparator(i)) {
        if (itemsSeen == currentIndex) {
          return DateSeparator(date: widget.messages[i].createdAt);
        }
        itemsSeen++;
      }
      
      // Check if this is the message we want
      if (itemsSeen == currentIndex) {
        messageIndex = i;
        break;
      }
      itemsSeen++;
    }
    
    // Build message bubble
    return _buildMessageBubble(messageIndex);
  }

  /// Check if we should show a date separator before this message
  bool _shouldShowDateSeparator(int index) {
    if (index == 0) return true; // Always show date for first message
    
    final currentMessage = widget.messages[index];
    final previousMessage = widget.messages[index - 1];
    
    // Show separator if messages are on different days
    final currentDate = DateTime(
      currentMessage.createdAt.year,
      currentMessage.createdAt.month,
      currentMessage.createdAt.day,
    );
    final previousDate = DateTime(
      previousMessage.createdAt.year,
      previousMessage.createdAt.month,
      previousMessage.createdAt.day,
    );
    
    return currentDate != previousDate;
  }

  /// Build message bubble with proper grouping
  Widget _buildMessageBubble(int index) {
    final message = widget.messages[index];
    final isFromCurrentUser = message.senderId == widget.currentUserId;
    
    // Determine message grouping
    final isFirstInGroup = _isFirstInGroup(index);
    final isLastInGroup = _isLastInGroup(index);
    
    // Create unique key for message
    final messageKey = _messageKeys.putIfAbsent(
      message.id,
      () => GlobalKey(),
    );

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
  }

  /// Check if message is first in a group (same sender)
  bool _isFirstInGroup(int index) {
    if (index == 0) return true;
    
    final currentMessage = widget.messages[index];
    final previousMessage = widget.messages[index - 1];
    
    // Different sender
    if (currentMessage.senderId != previousMessage.senderId) return true;
    
    // More than 5 minutes apart
    final timeDiff = currentMessage.createdAt.difference(previousMessage.createdAt);
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
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
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
