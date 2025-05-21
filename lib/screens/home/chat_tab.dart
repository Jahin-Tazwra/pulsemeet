import 'package:flutter/material.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'package:pulsemeet/models/direct_message.dart';
import 'package:pulsemeet/services/supabase_service.dart';
import 'package:pulsemeet/services/direct_message_service.dart';
import 'package:pulsemeet/screens/pulse/pulse_chat_screen.dart';
import 'package:pulsemeet/screens/chat/direct_message_screen.dart';
import 'package:pulsemeet/widgets/avatar.dart';
import 'package:provider/provider.dart' as provider_pkg;
import 'package:intl/intl.dart';
// import 'package:timeago/timeago.dart' as timeago;

/// Tab for displaying chats (both pulse chats and direct messages)
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _directMessageService = DirectMessageService();

  List<Pulse> _joinedPulses = [];
  List<Conversation> _conversations = [];
  bool _isLoadingPulses = true;
  bool _isLoadingConversations = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();

    // Listen for conversation updates
    _directMessageService.conversationsStream.listen((conversations) {
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _isLoadingConversations = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Fetch data for both tabs
  Future<void> _fetchData() async {
    _fetchJoinedPulses();
    _fetchConversations();
  }

  /// Fetch pulses the user has joined
  Future<void> _fetchJoinedPulses() async {
    setState(() {
      _isLoadingPulses = true;
      _errorMessage = '';
    });

    try {
      final supabaseService =
          provider_pkg.Provider.of<SupabaseService>(context, listen: false);
      final pulses = await supabaseService.getJoinedPulses();

      if (mounted) {
        setState(() {
          _joinedPulses = pulses;
          _isLoadingPulses = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPulses = false;
          _errorMessage = 'Error fetching joined pulses: ${e.toString()}';
        });
      }
    }
  }

  /// Fetch conversations
  Future<void> _fetchConversations() async {
    setState(() {
      _isLoadingConversations = true;
    });

    try {
      await _directMessageService.fetchConversations();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingConversations = false;
          _errorMessage = 'Error fetching conversations: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withAlpha(180),
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Pulse Chats'),
            Tab(text: 'Direct Messages'),
          ],
        ),
        // Removed refresh button to create a cleaner interface
        // Real-time updates will be used instead
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPulseChatsTab(),
          _buildDirectMessagesTab(),
        ],
      ),
    );
  }

  Widget _buildPulseChatsTab() {
    if (_isLoadingPulses) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1E88E5)),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: _fetchJoinedPulses,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_joinedPulses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 64.0,
              color: Color(0xFF64B5F6), // Light blue
            ),
            const SizedBox(height: 16.0),
            const Text(
              'No pulse chats',
              style: TextStyle(fontSize: 18.0),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            const Text(
              'Join a pulse to start chatting with participants',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64B5F6)),
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: _fetchJoinedPulses,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchJoinedPulses,
      child: ListView.builder(
        itemCount: _joinedPulses.length,
        itemBuilder: (context, index) {
          final pulse = _joinedPulses[index];

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.people, color: Colors.white),
            ),
            title: Text(pulse.title),
            subtitle: Text(
              pulse.description.length > 50
                  ? '${pulse.description.substring(0, 47)}...'
                  : pulse.description,
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatDate(pulse.startTime),
                  style: const TextStyle(fontSize: 12.0),
                ),
                const SizedBox(height: 4.0),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: _getPulseStatusColor(pulse),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Text(
                    _getPulseStatus(pulse),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.0,
                    ),
                  ),
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PulseChatScreen(pulse: pulse),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDirectMessagesTab() {
    if (_isLoadingConversations) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1E88E5)),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: _fetchConversations,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.message_outlined,
              size: 64.0,
              color: Color(0xFF64B5F6), // Light blue
            ),
            const SizedBox(height: 16.0),
            const Text(
              'No direct messages',
              style: TextStyle(fontSize: 18.0),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            const Text(
              'Connect with other users to start direct messaging',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64B5F6)),
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () {
                // Navigate to connections screen
                Navigator.pushNamed(context, '/connections');
              },
              child: const Text('View Connections'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchConversations,
      child: ListView.builder(
        itemCount: _conversations.length,
        itemBuilder: (context, index) {
          final conversation = _conversations[index];
          final profile = conversation.profile;
          final latestMessage = conversation.latestMessage;

          return ListTile(
            leading: UserAvatar(
              userId: profile.id,
              avatarUrl: profile.avatarUrl,
              size: 48.0,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    profile.displayName ?? profile.username ?? 'User',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (latestMessage != null)
                  Text(
                    _formatMessageTime(latestMessage.createdAt),
                    style: const TextStyle(
                      fontSize: 12.0,
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
            subtitle: Row(
              children: [
                Expanded(
                  child: latestMessage != null
                      ? Text(
                          _getMessagePreview(latestMessage),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: conversation.unreadCount > 0
                                ? Colors.black
                                : Colors.grey,
                            fontWeight: conversation.unreadCount > 0
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        )
                      : const Text(
                          'No messages yet',
                          style: TextStyle(
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                ),
                if (conversation.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.all(6.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      conversation.unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DirectMessageScreen(
                    otherUserId: profile.id,
                    otherUserProfile: profile,
                  ),
                ),
              ).then((_) => _fetchConversations());
            },
          );
        },
      ),
    );
  }

  /// Format date for pulse chats
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateToCheck = DateTime(date.year, date.month, date.day);

    if (dateToCheck == today) {
      return 'Today';
    } else if (dateToCheck == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else if (dateToCheck.isAfter(today.subtract(const Duration(days: 7)))) {
      return DateFormat('EEEE').format(date); // Day of week
    } else {
      return DateFormat('MMM d').format(date); // Month and day
    }
  }

  /// Format time for direct messages
  String _formatMessageTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(time.year, time.month, time.day);

    if (messageDate == today) {
      return DateFormat('h:mm a').format(time);
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else if (now.difference(time).inDays < 7) {
      return DateFormat('EEE').format(time); // Short day name
    } else {
      return DateFormat('M/d/yy').format(time);
    }
  }

  /// Get pulse status text
  String _getPulseStatus(Pulse pulse) {
    final now = DateTime.now();

    if (now.isBefore(pulse.startTime)) {
      return 'Upcoming';
    } else if (now.isAfter(pulse.endTime)) {
      return 'Ended';
    } else {
      return 'Active';
    }
  }

  /// Get pulse status color
  Color _getPulseStatusColor(Pulse pulse) {
    final now = DateTime.now();

    if (now.isBefore(pulse.startTime)) {
      return const Color(0xFF64B5F6); // Light blue
    } else if (now.isAfter(pulse.endTime)) {
      return const Color(0xFF9E9E9E); // Medium grey
    } else {
      return const Color(0xFF1E88E5); // Blue for active
    }
  }

  /// Get message preview text
  String _getMessagePreview(DirectMessage message) {
    if (message.isDeleted) {
      return 'This message was deleted';
    }

    switch (message.messageType) {
      case 'text':
        return message.content;
      case 'image':
        return '📷 Image';
      case 'video':
        return '🎥 Video';
      case 'audio':
        return '🎵 Voice message';
      case 'location':
        return '📍 Location';
      case 'liveLocation':
        return '📍 Live location';
      default:
        return message.content;
    }
  }
}
