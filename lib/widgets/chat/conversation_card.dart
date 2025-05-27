import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/widgets/avatar.dart';

/// Card widget for displaying conversation in the conversations list
class ConversationCard extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ConversationCard({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';

    // Get display information
    final displayTitle = conversation.getDisplayTitle(currentUserId);
    final displayAvatar = conversation.getDisplayAvatar(currentUserId);
    final hasUnread = (conversation.unreadCount ?? 0) > 0;
    final lastMessageTime =
        conversation.lastMessageAt ?? conversation.updatedAt;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: hasUnread
              ? (isDark
                  ? Colors.blue.withOpacity(0.1)
                  : Colors.blue.withOpacity(0.05))
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            _buildAvatar(displayAvatar, displayTitle, isDark),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and timestamp row
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            // Conversation type indicator
                            _buildTypeIndicator(isDark),
                            const SizedBox(width: 4),

                            // Title
                            Expanded(
                              child: Text(
                                displayTitle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: hasUnread
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Timestamp
                      Text(
                        _formatTimestamp(lastMessageTime),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hasUnread
                              ? theme.primaryColor
                              : (isDark ? Colors.grey[400] : Colors.grey[600]),
                          fontWeight:
                              hasUnread ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Last message and unread count row
                  Row(
                    children: [
                      // Last message preview
                      Expanded(
                        child: Text(
                          conversation.lastMessagePreview ?? 'No messages yet',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: hasUnread
                                ? (isDark ? Colors.white70 : Colors.black87)
                                : (isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600]),
                            fontWeight:
                                hasUnread ? FontWeight.w500 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // Unread count badge
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        _buildUnreadBadge(conversation.unreadCount!, theme),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build avatar widget
  Widget _buildAvatar(String? avatarUrl, String displayTitle, bool isDark) {
    return Stack(
      children: [
        UserAvatar(
          userId: conversation.participants?.isNotEmpty == true
              ? conversation.participants!.first.userId
              : '',
          avatarUrl: avatarUrl,
          displayName: conversation.participants?.isNotEmpty == true
              ? conversation.participants!.first.displayName
              : null,
          username: conversation.participants?.isNotEmpty == true
              ? conversation.participants!.first.username
              : null,
          size: 56,
          skipProfileLoad:
              true, // Skip database call since we have participant data
        ),

        // Online indicator for direct messages
        if (conversation.isDirectMessage)
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? const Color(0xFF121212) : Colors.white,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Build conversation type indicator
  Widget _buildTypeIndicator(bool isDark) {
    IconData icon;
    Color color;

    switch (conversation.type) {
      case ConversationType.pulseGroup:
        icon = Icons.groups;
        color = Colors.orange;
        break;
      case ConversationType.directMessage:
        icon = Icons.person;
        color = Colors.blue;
        break;
      case ConversationType.groupChat:
        icon = Icons.group;
        color = Colors.green;
        break;
    }

    return Icon(
      icon,
      size: 14,
      color: color,
    );
  }

  /// Build unread count badge
  Widget _buildUnreadBadge(int count, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.primaryColor,
        borderRadius: BorderRadius.circular(10),
      ),
      constraints: const BoxConstraints(
        minWidth: 20,
        minHeight: 20,
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// Format timestamp for display
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      // Today - show time
      final hour = timestamp.hour;
      final minute = timestamp.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    } else if (difference.inDays == 1) {
      // Yesterday
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      // This week - show day name
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[timestamp.weekday - 1];
    } else {
      // Older - show date
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}

/// Conversation card with swipe actions
class SwipeableConversationCard extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback? onArchive;
  final VoidCallback? onMute;
  final VoidCallback? onDelete;

  const SwipeableConversationCard({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onArchive,
    this.onMute,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: Key(conversation.id),
      background: Container(
        color: Colors.blue,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(
          Icons.archive,
          color: Colors.white,
          size: 24,
        ),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
          size: 24,
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Archive action
          onArchive?.call();
          return false; // Don't actually dismiss
        } else if (direction == DismissDirection.endToStart) {
          // Delete action - show confirmation
          return await _showDeleteConfirmation(context);
        }
        return false;
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          onDelete?.call();
        }
      },
      child: ConversationCard(
        conversation: conversation,
        onTap: onTap,
        onLongPress: () => _showContextMenu(context),
      ),
    );
  }

  /// Show delete confirmation dialog
  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Conversation'),
            content: const Text(
              'Are you sure you want to delete this conversation? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Show context menu with options
  void _showContextMenu(BuildContext context) {
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
            ListTile(
              leading: Icon(
                  conversation.isMuted ? Icons.volume_up : Icons.volume_off),
              title: Text(conversation.isMuted ? 'Unmute' : 'Mute'),
              onTap: () {
                Navigator.pop(context);
                onMute?.call();
              },
            ),
            ListTile(
              leading: Icon(
                  conversation.isArchived ? Icons.unarchive : Icons.archive),
              title: Text(conversation.isArchived ? 'Unarchive' : 'Archive'),
              onTap: () {
                Navigator.pop(context);
                onArchive?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await _showDeleteConfirmation(context);
                if (confirmed) {
                  onDelete?.call();
                }
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
