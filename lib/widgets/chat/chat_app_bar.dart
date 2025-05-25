import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/widgets/avatar.dart';

/// Custom app bar for chat screen with conversation info and actions
class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Conversation conversation;
  final VoidCallback onBackPressed;
  final VoidCallback? onInfoPressed;
  final VoidCallback? onCallPressed;
  final VoidCallback? onVideoCallPressed;

  const ChatAppBar({
    super.key,
    required this.conversation,
    required this.onBackPressed,
    this.onInfoPressed,
    this.onCallPressed,
    this.onVideoCallPressed,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';

    // Get display information
    final displayTitle = conversation.getDisplayTitle(currentUserId);
    final displayAvatar = conversation.getDisplayAvatar(currentUserId);

    return AppBar(
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF212121) : Colors.white,
      foregroundColor: isDark ? Colors.white : Colors.black,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBackPressed,
      ),
      title: InkWell(
        onTap: onInfoPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              // Avatar
              UserAvatar(
                userId: conversation.participants?.isNotEmpty == true
                    ? conversation.participants!.first.id
                    : '',
                avatarUrl: displayAvatar,
                size: 40,
              ),
              const SizedBox(width: 12),

              // Title and subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title with type indicator
                    Row(
                      children: [
                        _buildTypeIndicator(),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            displayTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    // Subtitle with encryption indicator
                    Row(
                      children: [
                        Text(
                          _getSubtitle(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        if (conversation.encryptionEnabled) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.lock,
                            size: 12,
                            color: Colors.green,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: _buildActions(context, isDark),
    );
  }

  /// Build conversation type indicator
  Widget _buildTypeIndicator() {
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

  /// Get subtitle text based on conversation type
  String _getSubtitle() {
    switch (conversation.type) {
      case ConversationType.pulseGroup:
        final participantCount = conversation.participants?.length ?? 0;
        return participantCount > 0
            ? '$participantCount participants'
            : 'Pulse Group';
      case ConversationType.directMessage:
        return 'Online'; // TODO: Get actual online status
      case ConversationType.groupChat:
        final participantCount = conversation.participants?.length ?? 0;
        return participantCount > 0
            ? '$participantCount members'
            : 'Group Chat';
    }
  }

  /// Build action buttons
  List<Widget> _buildActions(BuildContext context, bool isDark) {
    final actions = <Widget>[];

    // Voice call button (only for direct messages)
    if (conversation.isDirectMessage && onCallPressed != null) {
      actions.add(
        IconButton(
          icon: const Icon(Icons.call),
          onPressed: onCallPressed,
          tooltip: 'Voice Call',
        ),
      );
    }

    // Video call button (only for direct messages)
    if (conversation.isDirectMessage && onVideoCallPressed != null) {
      actions.add(
        IconButton(
          icon: const Icon(Icons.videocam),
          onPressed: onVideoCallPressed,
          tooltip: 'Video Call',
        ),
      );
    }

    // More options menu
    actions.add(
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) => _handleMenuAction(context, value),
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'info',
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Conversation Info'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (conversation.isDirectMessage) ...[
            const PopupMenuItem(
              value: 'block',
              child: ListTile(
                leading: Icon(Icons.block, color: Colors.red),
                title: Text('Block User', style: TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          PopupMenuItem(
            value: 'mute',
            child: ListTile(
              leading: Icon(
                  conversation.isMuted ? Icons.volume_up : Icons.volume_off),
              title: Text(conversation.isMuted ? 'Unmute' : 'Mute'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'search',
            child: ListTile(
              leading: Icon(Icons.search),
              title: Text('Search Messages'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'export',
            child: ListTile(
              leading: Icon(Icons.download),
              title: Text('Export Chat'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'clear',
            child: ListTile(
              leading: Icon(Icons.clear_all, color: Colors.red),
              title:
                  Text('Clear Messages', style: TextStyle(color: Colors.red)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );

    return actions;
  }

  /// Handle menu action selection
  void _handleMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'info':
        onInfoPressed?.call();
        break;
      case 'block':
        _showBlockUserDialog(context);
        break;
      case 'mute':
        _toggleMute(context);
        break;
      case 'search':
        _showSearchMessages(context);
        break;
      case 'export':
        _exportChat(context);
        break;
      case 'clear':
        _showClearMessagesDialog(context);
        break;
    }
  }

  /// Show block user confirmation dialog
  void _showBlockUserDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: const Text(
          'Are you sure you want to block this user? You will no longer receive messages from them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement block user functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Block user functionality coming soon!')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  /// Toggle mute status
  void _toggleMute(BuildContext context) {
    // TODO: Implement mute/unmute functionality
    final action = conversation.isMuted ? 'unmuted' : 'muted';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Conversation $action')),
    );
  }

  /// Show search messages
  void _showSearchMessages(BuildContext context) {
    // TODO: Implement message search
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message search coming soon!')),
    );
  }

  /// Export chat
  void _exportChat(BuildContext context) {
    // TODO: Implement chat export
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat export coming soon!')),
    );
  }

  /// Show clear messages confirmation dialog
  void _showClearMessagesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Messages'),
        content: const Text(
          'Are you sure you want to clear all messages in this conversation? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement clear messages functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Clear messages functionality coming soon!')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
