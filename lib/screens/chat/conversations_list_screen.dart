import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/conversation_service.dart';
import 'package:pulsemeet/screens/chat/chat_screen.dart';
import 'package:pulsemeet/screens/profile/user_search_screen.dart';
import 'package:pulsemeet/widgets/chat/conversation_card.dart';
import 'package:pulsemeet/widgets/common/loading_indicator.dart';
import 'package:pulsemeet/widgets/common/error_widget.dart';

/// Modern conversations list screen showing all conversations (pulse groups + DMs)
class ConversationsListScreen extends StatefulWidget {
  const ConversationsListScreen({super.key});

  @override
  State<ConversationsListScreen> createState() =>
      _ConversationsListScreenState();
}

class _ConversationsListScreenState extends State<ConversationsListScreen>
    with AutomaticKeepAliveClientMixin {
  final ConversationService _conversationService = ConversationService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<List<Conversation>>? _conversationsSubscription;
  List<Conversation> _allConversations = [];
  List<Conversation> _filteredConversations = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String _searchQuery = '';
  String? _errorMessage;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeConversations();
    _setupSearch();
  }

  @override
  void dispose() {
    _conversationsSubscription?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Initialize conversations and subscribe to updates
  Future<void> _initializeConversations() async {
    try {
      debugPrint('🚀 Initializing conversations list');

      // Set a timeout for initialization
      final initializationTimeout = Timer(const Duration(seconds: 20), () {
        if (mounted && _isLoading) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Loading conversations timed out. Please try again.';
          });
          debugPrint('⏰ Conversations initialization timed out');
        }
      });

      // Set a fallback timeout to ensure we never stay in loading state indefinitely
      final fallbackTimeout = Timer(const Duration(seconds: 5), () {
        if (mounted && _isLoading) {
          debugPrint('⏰ Fallback timeout - showing empty state');
          setState(() {
            _allConversations = [];
            _filterConversations();
            _isLoading = false;
            _errorMessage = null;
          });
        }
      });

      // Subscribe to conversations stream
      _conversationsSubscription =
          _conversationService.conversationsStream.listen(
        (conversations) {
          if (mounted) {
            initializationTimeout.cancel(); // Cancel timeout on success
            fallbackTimeout.cancel(); // Cancel fallback timeout
            setState(() {
              _allConversations = conversations;
              _filterConversations();
              _isLoading = false;
              _errorMessage = null;
            });
            debugPrint('📨 UI received ${conversations.length} conversations');
          }
        },
        onError: (error) {
          if (mounted) {
            initializationTimeout.cancel(); // Cancel timeout on error
            fallbackTimeout.cancel(); // Cancel fallback timeout
            setState(() {
              _isLoading = false;
              _errorMessage = 'Failed to load conversations: $error';
            });
          }
          debugPrint('❌ Error in conversations stream: $error');
        },
      );

      // Start listening to conversations with timeout
      await _conversationService.subscribeToConversations().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⏰ Subscription setup timed out');
          throw TimeoutException(
              'Subscription timed out', const Duration(seconds: 10));
        },
      );

      debugPrint('✅ Conversation subscription setup completed');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e is TimeoutException
              ? 'Connection timed out. Please check your internet connection.'
              : 'Failed to initialize conversations: $e';
        });
      }
      debugPrint('❌ Error initializing conversations: $e');
    }
  }

  /// Setup search functionality
  void _setupSearch() {
    _searchController.addListener(() {
      final query = _searchController.text.trim();
      if (query != _searchQuery) {
        setState(() {
          _searchQuery = query;
          _isSearching = query.isNotEmpty;
        });
        _filterConversations();
      }
    });
  }

  /// Filter conversations based on search query
  void _filterConversations() {
    if (_searchQuery.isEmpty) {
      _filteredConversations = List.from(_allConversations);
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredConversations = _allConversations.where((conversation) {
        final currentUserId =
            Supabase.instance.client.auth.currentUser?.id ?? '';
        final title = conversation.getDisplayTitle(currentUserId).toLowerCase();
        final lastMessage =
            conversation.lastMessagePreview?.toLowerCase() ?? '';

        return title.contains(query) || lastMessage.contains(query);
      }).toList();
    }

    // Sort conversations by last message time
    _filteredConversations.sort((a, b) {
      final aTime = a.lastMessageAt ?? a.updatedAt;
      final bTime = b.lastMessageAt ?? b.updatedAt;
      return bTime.compareTo(aTime);
    });
  }

  /// Refresh conversations
  Future<void> _refreshConversations() async {
    try {
      await _conversationService.subscribeToConversations();
    } catch (e) {
      debugPrint('❌ Error refreshing conversations: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh conversations: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Navigate to chat screen
  void _openChat(Conversation conversation) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatScreen(conversation: conversation),
      ),
    );
  }

  /// Show new conversation options
  void _showNewConversationOptions() {
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
            Text(
              'Start New Conversation',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('New Direct Message'),
              subtitle: const Text('Start a private conversation'),
              onTap: () {
                Navigator.pop(context);
                _startDirectMessage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add),
              title: const Text('Create Group Chat'),
              subtitle: const Text('Start a group conversation'),
              onTap: () {
                Navigator.pop(context);
                _createGroupChat();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Start a new direct message
  void _startDirectMessage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UserSearchScreen(
          title: 'New Direct Message',
          onUserSelected: (Profile user) async {
            Navigator.pop(context);

            // Create or get direct conversation
            final conversation =
                await _conversationService.createDirectConversation(user.id);
            if (conversation != null && mounted) {
              _openChat(conversation);
            }
          },
        ),
      ),
    );
  }

  /// Create a new group chat
  void _createGroupChat() {
    // TODO: Implement group chat creation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Group chat creation coming soon!'),
      ),
    );
  }

  /// Clear search
  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _isSearching = false;
    });
    _filterConversations();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search conversations...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 18,
                ),
              )
            : const Text(
                'Messages',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearSearch,
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewConversationOptions,
        backgroundColor: theme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: LoadingIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: CustomErrorWidget(
          message: _errorMessage!,
          onRetry: _initializeConversations,
        ),
      );
    }

    if (_filteredConversations.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _refreshConversations,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _filteredConversations.length,
        itemBuilder: (context, index) {
          final conversation = _filteredConversations[index];
          return ConversationCard(
            conversation: conversation,
            onTap: () => _openChat(conversation),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No conversations found',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with different keywords',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[500] : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a new conversation to get started',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.grey[500] : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showNewConversationOptions,
            icon: const Icon(Icons.add),
            label: const Text('Start Conversation'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
