import 'package:flutter/material.dart';
import 'package:pulsemeet/models/connection.dart';
import 'package:pulsemeet/services/connection_service.dart';
import 'package:pulsemeet/services/conversation_service.dart';
import 'package:pulsemeet/screens/profile/user_profile_screen.dart';
import 'package:pulsemeet/screens/connections/user_search_screen.dart';
import 'package:pulsemeet/screens/connections/connection_requests_screen.dart';
import 'package:pulsemeet/screens/chat/chat_screen.dart';
import 'package:pulsemeet/widgets/profile/profile_list_item.dart';

/// Screen for viewing and managing connections
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final _connectionService = ConnectionService();
  final _conversationService = ConversationService();

  bool _isLoading = true;
  List<Connection> _connections = [];
  List<Connection> _pendingRequests = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  /// Fetch connections and pending requests
  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final connections = await _connectionService.fetchConnections();
      final pendingRequests = await _connectionService.fetchPendingRequests();

      if (mounted) {
        setState(() {
          _connections = connections;
          _pendingRequests = pendingRequests;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error fetching connections: ${e.toString()}';
        });
      }
    }
  }

  /// Remove a connection
  Future<void> _removeConnection(Connection connection) async {
    final currentUserId = _connectionService.currentUserId;
    if (currentUserId == null) return;

    final otherUserProfile = connection.getOtherUserProfile(currentUserId);
    final otherUserName =
        otherUserProfile?.displayName ?? otherUserProfile?.username ?? 'User';

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Connection'),
        content: Text(
            'Are you sure you want to remove $otherUserName from your connections?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _connectionService.removeConnection(connection.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$otherUserName removed from your connections'),
            duration: const Duration(seconds: 2),
          ),
        );

        // Refresh the list
        _fetchData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing connection: ${e.toString()}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Start a direct message with a user
  Future<void> _startDirectMessage(String otherUserId) async {
    try {
      // Create or get direct conversation
      final conversation =
          await _conversationService.createDirectConversation(otherUserId);

      if (conversation != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(conversation: conversation),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create conversation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting conversation: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
        actions: [
          // Pending requests button with badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ConnectionRequestsScreen(),
                    ),
                  ).then((_) => _fetchData());
                },
                tooltip: 'Connection Requests',
              ),
              if (_pendingRequests.isNotEmpty)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      _pendingRequests.length.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const UserSearchScreen(),
            ),
          ).then((_) => _fetchData());
        },
        tooltip: 'Find People',
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
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
              onPressed: _fetchData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_connections.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.people_outline,
              size: 64.0,
              color: Colors.grey,
            ),
            const SizedBox(height: 16.0),
            const Text(
              'No connections yet',
              style: TextStyle(fontSize: 18.0),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            const Text(
              'Connect with other users to chat and interact',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16.0),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UserSearchScreen(),
                  ),
                ).then((_) => _fetchData());
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Find People'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView.builder(
        itemCount: _connections.length,
        itemBuilder: (context, index) {
          final connection = _connections[index];
          final currentUserId = _connectionService.currentUserId;
          if (currentUserId == null) return const SizedBox.shrink();

          final otherUserProfile =
              connection.getOtherUserProfile(currentUserId);

          if (otherUserProfile == null) {
            return const SizedBox.shrink();
          }

          return ProfileListItem(
            profile: otherUserProfile,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      UserProfileScreen(userId: otherUserProfile.id),
                ),
              );
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.message_outlined),
                  onPressed: () => _startDirectMessage(otherUserProfile.id),
                  tooltip: 'Message',
                ),
                IconButton(
                  icon: const Icon(Icons.person_remove_outlined),
                  onPressed: () => _removeConnection(connection),
                  tooltip: 'Remove Connection',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
