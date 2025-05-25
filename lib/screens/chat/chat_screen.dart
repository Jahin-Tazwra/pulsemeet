import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/services/conversation_service.dart';
import 'package:pulsemeet/widgets/chat/message_list.dart';
import 'package:pulsemeet/widgets/chat/unified_message_input.dart';
import 'package:pulsemeet/widgets/chat/typing_indicator.dart';
import 'package:pulsemeet/widgets/chat/chat_app_bar.dart';
import 'package:pulsemeet/widgets/common/loading_indicator.dart';
import 'package:pulsemeet/widgets/common/error_widget.dart';

/// Unified chat screen that adapts to conversation type (pulse group vs direct message)
class ChatScreen extends StatefulWidget {
  final Conversation conversation;

  const ChatScreen({
    super.key,
    required this.conversation,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final ConversationService _conversationService = ConversationService();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<List<Message>>? _messagesSubscription;
  StreamSubscription<Message>? _newMessageSubscription;
  StreamSubscription<Map<String, List<String>>>? _typingSubscription;

  List<Message> _messages = [];
  List<String> _typingUsers = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  String? _errorMessage;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _initializeChat();
    _setupScrollListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messagesSubscription?.cancel();
    _newMessageSubscription?.cancel();
    _typingSubscription?.cancel();
    _conversationService.unsubscribeFromMessages();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // Mark messages as read when app comes to foreground
      _markMessagesAsRead();
    }
  }

  /// Initialize chat and subscribe to messages
  Future<void> _initializeChat() async {
    try {
      debugPrint(
          '🚀 Initializing chat for conversation: ${widget.conversation.id}');

      // Subscribe to messages stream
      _messagesSubscription = _conversationService.messagesStream.listen(
        (messages) {
          if (mounted) {
            setState(() {
              _messages = messages;
              _isLoading = false;
              _errorMessage = null;
            });

            // Auto-scroll to bottom for new messages
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToBottom();
            });

            // Mark messages as read
            _markMessagesAsRead();
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Failed to load messages: $error';
            });
          }
          debugPrint('❌ Error in messages stream: $error');
        },
      );

      // Subscribe to new messages for real-time updates
      _newMessageSubscription = _conversationService.newMessageStream.listen(
        (message) {
          if (mounted && message.conversationId == widget.conversation.id) {
            // Add optimistic message if not already in list
            if (!_messages.any((m) => m.id == message.id)) {
              setState(() {
                _messages.add(message);
                _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
              });

              // Auto-scroll for own messages or if user is at bottom
              if (message.senderId == _currentUserId || _isUserAtBottom()) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });
              }
            }
          }
        },
      );

      // Subscribe to typing indicators
      _typingSubscription = _conversationService.typingStatusStream.listen(
        (typingMap) {
          final typingUsers = typingMap[widget.conversation.id] ?? [];
          if (mounted) {
            setState(() {
              _typingUsers = typingUsers;
            });
          }
        },
      );

      // Start listening to messages for this conversation
      await _conversationService.subscribeToMessages(widget.conversation.id);

      // Subscribe to typing status
      await _conversationService
          .subscribeToTypingStatus(widget.conversation.id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to initialize chat: $e';
        });
      }
      debugPrint('❌ Error initializing chat: $e');
    }
  }

  /// Setup scroll listener for pagination
  void _setupScrollListener() {
    _scrollController.addListener(() {
      // Load more messages when scrolled to top
      if (_scrollController.position.pixels <= 100 &&
          !_isLoadingMore &&
          _hasMoreMessages) {
        _loadMoreMessages();
      }
    });
  }

  /// Load more messages (pagination)
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      // TODO: Implement pagination in conversation service
      // For now, we'll just mark as no more messages
      setState(() {
        _hasMoreMessages = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
      debugPrint('❌ Error loading more messages: $e');
    }
  }

  /// Check if user is at the bottom of the chat
  bool _isUserAtBottom() {
    if (!_scrollController.hasClients) return true;

    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - 100;
  }

  /// Scroll to bottom of chat
  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;

    if (animate) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  /// Mark messages as read
  void _markMessagesAsRead() {
    _conversationService.markMessagesAsRead(widget.conversation.id);
  }

  /// Send a text message
  Future<void> _sendTextMessage(String content) async {
    if (content.trim().isEmpty) return;

    try {
      await _conversationService.sendTextMessage(
        widget.conversation.id,
        content.trim(),
      );
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Send an image message
  Future<void> _sendImageMessage(String imagePath, {String? caption}) async {
    try {
      await _conversationService.sendImageMessage(
        widget.conversation.id,
        imagePath as dynamic, // TODO: Fix type
        caption: caption,
      );
    } catch (e) {
      debugPrint('❌ Error sending image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Handle typing status
  void _onTypingChanged(bool isTyping) {
    _conversationService.setTypingStatus(widget.conversation.id, isTyping);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBar: ChatAppBar(
        conversation: widget.conversation,
        onBackPressed: () => Navigator.of(context).pop(),
        onInfoPressed: () => _showConversationInfo(),
        onCallPressed:
            widget.conversation.isDirectMessage ? () => _startCall() : null,
        onVideoCallPressed: widget.conversation.isDirectMessage
            ? () => _startVideoCall()
            : null,
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _buildMessagesList(),
          ),

          // Typing indicator
          if (_typingUsers.isNotEmpty)
            TypingIndicator(
              typingUsers: _typingUsers,
              conversation: widget.conversation,
            ),

          // Message input
          UnifiedMessageInput(
            conversation: widget.conversation,
            onSendText: _sendTextMessage,
            onSendImage: _sendImageMessage,
            onTypingChanged: _onTypingChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_isLoading) {
      return const Center(child: LoadingIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: CustomErrorWidget(
          message: _errorMessage!,
          onRetry: _initializeChat,
        ),
      );
    }

    if (_messages.isEmpty) {
      return _buildEmptyState();
    }

    return MessageList(
      messages: _messages,
      conversation: widget.conversation,
      scrollController: _scrollController,
      isLoadingMore: _isLoadingMore,
      hasMoreMessages: _hasMoreMessages,
      currentUserId: _currentUserId ?? '',
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.conversation.isDirectMessage
                ? Icons.chat_bubble_outline
                : Icons.groups,
            size: 64,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            widget.conversation.isDirectMessage
                ? 'Start your conversation with ${widget.conversation.getDisplayTitle(currentUserId)}'
                : 'Welcome to ${widget.conversation.getDisplayTitle(currentUserId)}',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to get started',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.grey[500] : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// Show conversation info
  void _showConversationInfo() {
    // TODO: Implement conversation info screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Conversation info coming soon!'),
      ),
    );
  }

  /// Start voice call
  void _startCall() {
    // TODO: Implement voice calling
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Voice calling coming soon!'),
      ),
    );
  }

  /// Start video call
  void _startVideoCall() {
    // TODO: Implement video calling
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Video calling coming soon!'),
      ),
    );
  }
}
