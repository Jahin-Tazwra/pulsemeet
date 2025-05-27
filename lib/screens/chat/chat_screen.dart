import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/services/conversation_service.dart';
import 'package:pulsemeet/services/optimistic_ui_service.dart';
import 'package:pulsemeet/services/message_cache_service.dart';
import 'package:pulsemeet/services/firebase_messaging_service.dart';
import 'package:pulsemeet/widgets/chat/message_list.dart';
import 'package:pulsemeet/widgets/chat/unified_message_input.dart';
import 'package:pulsemeet/widgets/chat/typing_indicator.dart';
import 'package:pulsemeet/widgets/chat/chat_app_bar.dart';
import 'package:pulsemeet/widgets/common/loading_indicator.dart';
import 'package:pulsemeet/widgets/common/error_widget.dart';
import 'package:pulsemeet/widgets/debug/performance_monitor.dart';

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
  final OptimisticUIService _optimisticUI = OptimisticUIService.instance;
  final ScrollController _scrollController = ScrollController();
  final FirebaseMessagingService _firebaseMessaging =
      FirebaseMessagingService();

  StreamSubscription<List<Message>>? _optimisticMessagesSubscription;
  StreamSubscription<Map<String, List<String>>>? _typingSubscription;

  List<Message> _messages = [];
  List<String> _typingUsers = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  bool _isInitialLoadComplete = false; // Track if initial load is complete
  bool _hasScrolledToBottomOnce =
      false; // Track if we've scrolled to bottom for this chat session
  bool _isNavigationEntry = true; // Track if this is a fresh navigation entry
  double _lastKeyboardHeight = 0; // Track keyboard height changes
  String? _errorMessage;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;

    // Clear notifications for this conversation when it's opened
    _conversationService
        .clearNotificationsForConversation(widget.conversation.id);

    // CRITICAL FIX: Set this conversation as active to suppress notifications
    _firebaseMessaging.setActiveConversation(widget.conversation.id);

    // CRITICAL FIX: Check if we have cached messages synchronously
    _checkCachedMessagesSync();

    _initializeChat();
    _setupScrollListener();
  }

  /// Check for cached messages synchronously to prevent loading indicator flash
  void _checkCachedMessagesSync() {
    try {
      // CRITICAL FIX: First check OptimisticUI cache for instant restoration
      final optimisticMessages =
          _optimisticUI.getCachedMessages(widget.conversation.id);

      if (optimisticMessages.isNotEmpty) {
        debugPrint(
            '⚡ SYNC: Found ${optimisticMessages.length} messages in OptimisticUI cache');

        // CRITICAL FIX: Count read messages to verify status preservation
        final readMessages = optimisticMessages
            .where((m) => m.status == MessageStatus.read)
            .length;
        debugPrint(
            '⚡ SYNC: Found $readMessages read messages in cache - status should be preserved');

        // Set messages immediately to prevent empty state
        _messages = optimisticMessages;
        _isLoading = false;
        _isInitialLoadComplete = true;

        debugPrint(
            '⚡ SYNC: Restored ${optimisticMessages.length} messages from OptimisticUI cache - no loading indicator');

        // CRITICAL FIX: Scroll to bottom when cached messages are loaded
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint(
              '🔄 SCROLL DEBUG: Scrolling to bottom for OptimisticUI cached messages (navigation entry)');
          _scrollToBottomForNavigation();
        });
        return; // Exit early if we found OptimisticUI cache
      }

      // Fallback: Try to get cached messages from the message cache service directly
      final messageCache = MessageCacheService();
      final cachedMessageIds =
          messageCache.getConversationMessageIds(widget.conversation.id);

      debugPrint(
          '⚡ SYNC: Found ${cachedMessageIds.length} cached message IDs for conversation ${widget.conversation.id}');

      if (cachedMessageIds.isNotEmpty) {
        // Load the actual cached messages synchronously
        final cachedMessages = <Message>[];
        int foundMessages = 0;

        for (final messageId in cachedMessageIds) {
          final cachedMessage =
              messageCache.getCachedProcessedMessage(messageId);
          if (cachedMessage != null) {
            cachedMessages.add(cachedMessage);
            foundMessages++;
          }
        }

        debugPrint(
            '⚡ SYNC: Found $foundMessages actual cached messages out of ${cachedMessageIds.length} IDs');

        if (cachedMessages.isNotEmpty) {
          // Sort messages chronologically (oldest first)
          cachedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

          // Set messages immediately to prevent empty state
          _messages = cachedMessages;
          _isLoading = false;
          _isInitialLoadComplete = true;

          debugPrint(
              '⚡ SYNC: Loaded ${cachedMessages.length} cached messages immediately - no loading indicator');
          debugPrint(
              '⚡ SYNC: Message order - First: ${cachedMessages.first.createdAt}, Last: ${cachedMessages.last.createdAt}');

          // CRITICAL FIX: Scroll to bottom when cached messages are loaded
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint(
                '🔄 SCROLL DEBUG: Scrolling to bottom for cached messages (navigation entry)');
            _scrollToBottomForNavigation();
          });
        } else {
          debugPrint(
              '⚡ SYNC: Found message IDs but no cached message content - will show loading indicator');
        }
      } else {
        debugPrint(
            '⚡ SYNC: No cached message IDs found - will show loading indicator');
      }
    } catch (e) {
      debugPrint('⚡ SYNC: Error loading cached messages: $e');
      // Continue with loading indicator
    }
  }

  @override
  void dispose() {
    debugPrint('🧹 Disposing ChatScreen for: ${widget.conversation.id}');

    WidgetsBinding.instance.removeObserver(this);

    // CRITICAL FIX: Clear active conversation to re-enable notifications
    _firebaseMessaging.clearActiveConversation();

    // Cancel all subscriptions
    _optimisticMessagesSubscription?.cancel();
    _typingSubscription?.cancel();

    // CRITICAL FIX: Don't clear optimistic UI data to preserve messages between navigation
    // This allows messages to persist when user navigates back to the conversation
    // _optimisticUI.clearConversation(widget.conversation.id); // REMOVED

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

  /// Handle keyboard changes more reliably
  void _handleKeyboardChange(double currentKeyboardHeight) {
    // Only process if keyboard height actually changed
    if (currentKeyboardHeight != _lastKeyboardHeight) {
      debugPrint(
          '🔄 KEYBOARD DEBUG: Height changed from $_lastKeyboardHeight to $currentKeyboardHeight');

      final isKeyboardVisible = currentKeyboardHeight > 0;

      _lastKeyboardHeight = currentKeyboardHeight;

      // When keyboard appears or changes size
      if (isKeyboardVisible) {
        // Immediate scroll attempt
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _attemptKeyboardScroll();
        });

        // Backup scroll attempts with different delays
        Future.delayed(const Duration(milliseconds: 50), () {
          _attemptKeyboardScroll();
        });

        Future.delayed(const Duration(milliseconds: 150), () {
          _attemptKeyboardScroll();
        });

        Future.delayed(const Duration(milliseconds: 300), () {
          _attemptKeyboardScroll();
        });
      }
    }
  }

  /// Attempt to scroll when keyboard appears
  void _attemptKeyboardScroll() {
    if (!mounted || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    debugPrint(
        '🔄 KEYBOARD DEBUG: Attempting scroll - position=${position.pixels}, maxExtent=${position.maxScrollExtent}');

    // If user was near the bottom, keep them at the bottom
    if (position.pixels >= position.maxScrollExtent - 200) {
      debugPrint('🔄 KEYBOARD DEBUG: Executing scroll to bottom');

      // Use immediate jump for keyboard-triggered scrolls to be more responsive
      if (position.maxScrollExtent > 0) {
        _scrollController.jumpTo(position.maxScrollExtent);
      }
    }
  }

  /// Initialize chat and subscribe to messages
  Future<void> _initializeChat() async {
    try {
      debugPrint('🚀 🔥 CHAT INIT: ===== STARTING CHAT INITIALIZATION =====');
      debugPrint('🚀 🔥 CHAT INIT: Conversation: ${widget.conversation.id}');
      debugPrint(
          '🚀 🔥 CHAT INIT: Current UI message count: ${_messages.length}');

      // Ensure OptimisticUI status subscription is set up
      _conversationService.ensureOptimisticUIStatusSubscription();

      // CRITICAL FIX: Try to get cached messages synchronously first
      List<Message> initialMessages = [];

      // First, try to get messages from cache synchronously
      try {
        final cachedMessages = await _conversationService
            .getMessagesForConversation(widget.conversation.id);
        initialMessages = cachedMessages;
        debugPrint(
            '✅ Initial messages loaded: ${initialMessages.length} messages');
      } catch (e) {
        debugPrint('❌ Error loading initial messages: $e');
        // Continue with empty list - we'll load from server in background
      }

      // CRITICAL FIX: Check if we already have cached messages in UI state
      // If we do, don't overwrite them with potentially limited initialMessages
      final currentCachedMessages =
          _optimisticUI.getCachedMessages(widget.conversation.id);
      final messagesToUse = currentCachedMessages.isNotEmpty
          ? currentCachedMessages
          : initialMessages;

      debugPrint(
          '🚀 🔥 CHAT INIT: Current cached messages: ${currentCachedMessages.length}');
      debugPrint(
          '🚀 🔥 CHAT INIT: Initial messages from service: ${initialMessages.length}');
      debugPrint('🚀 🔥 CHAT INIT: Using messages: ${messagesToUse.length}');

      // CRITICAL FIX: Set UI state IMMEDIATELY with cached messages if available, otherwise initialMessages
      if (mounted) {
        setState(() {
          _messages = messagesToUse;
          _isLoading =
              messagesToUse.isEmpty; // Only show loading if no cached messages
          _isInitialLoadComplete = messagesToUse.isNotEmpty;
        });
        debugPrint(
            '⚡ UI state updated immediately with ${messagesToUse.length} messages (cached: ${currentCachedMessages.isNotEmpty})');
      }

      // Initialize optimistic UI with messages BEFORE setting up stream
      debugPrint(
          '🚀 🔥 CHAT INIT: About to call initializeWithMessages with ${initialMessages.length} messages');
      _optimisticUI.initializeWithMessages(
          widget.conversation.id, initialMessages);
      debugPrint('🚀 🔥 CHAT INIT: initializeWithMessages completed');

      // Now set up stream subscription - it will immediately receive the initialized messages
      debugPrint('🔔 Setting up optimistic UI stream subscription...');
      _optimisticMessagesSubscription = _optimisticUI
          .getOptimisticMessageStream(widget.conversation.id)
          .listen(
        (messages) {
          if (mounted) {
            final wasAtBottom = _isUserAtBottom();
            final previousMessageCount = _messages.length;

            // CRITICAL FIX: Better initial load detection
            // This is the first time we're getting messages for this chat session OR it's a fresh navigation
            final isFirstTimeGettingMessages =
                (_isNavigationEntry || !_hasScrolledToBottomOnce) &&
                    messages.isNotEmpty;

            debugPrint(
                '🔔 🔥 STREAM UPDATE: ===== RECEIVED STREAM UPDATE =====');
            debugPrint(
                '🔔 🔥 STREAM UPDATE: Conversation: ${widget.conversation.id}');
            debugPrint(
                '🔔 🔥 STREAM UPDATE: Previous message count: $previousMessageCount');
            debugPrint(
                '🔔 🔥 STREAM UPDATE: New message count: ${messages.length}');
            debugPrint(
                '🔔 🔥 STREAM UPDATE: isFirstTimeGettingMessages=$isFirstTimeGettingMessages, _hasScrolledToBottomOnce=$_hasScrolledToBottomOnce');

            if (messages.isNotEmpty) {
              debugPrint(
                  '🔔 🔥 STREAM UPDATE: First message: ${messages.first.createdAt} (${messages.first.id})');
              debugPrint(
                  '🔔 🔥 STREAM UPDATE: Last message: ${messages.last.createdAt} (${messages.last.id})');
            }

            // Debug: Check if any message status changed
            if (_messages.isNotEmpty && messages.isNotEmpty) {
              for (int i = 0;
                  i < messages.length && i < _messages.length;
                  i++) {
                if (messages[i].status != _messages[i].status) {
                  debugPrint(
                      '🔔 CHAT SCREEN: Message ${messages[i].id} status changed from ${_messages[i].status} to ${messages[i].status}');
                }
              }
            }

            setState(() {
              _messages = messages;
              // Always set _isLoading = false when we get the stream update
              // The empty state check will handle showing loading vs empty state
              _isLoading = false;
              _errorMessage = null;
              // CRITICAL FIX: Mark initial load as complete regardless of message count
              // This ensures empty conversations don't stay in loading state forever
              _isInitialLoadComplete = true;
            });

            // CRITICAL FIX: Enhanced auto-scroll logic for navigation scenarios
            final hasNewMessages = messages.length > previousMessageCount;

            // Always scroll to bottom in these cases:
            // 1. First time getting messages for this chat session (navigation to chat)
            // 2. User was at bottom and new messages arrived
            // 3. New message is from current user
            final shouldScroll = isFirstTimeGettingMessages ||
                (hasNewMessages && wasAtBottom) ||
                (hasNewMessages && _shouldAutoScroll(messages));

            if (shouldScroll) {
              // CRITICAL FIX: For navigation (first time), use special navigation scroll
              // For new messages, use smooth animation
              debugPrint(
                  '🔄 SCROLL DEBUG: Triggering scroll - isFirstTime=$isFirstTimeGettingMessages, isNavigation=$_isNavigationEntry');

              if (isFirstTimeGettingMessages) {
                _scrollToBottomForNavigation();
              } else {
                _scrollToBottom(animate: true);
              }
            }

            // Navigation scroll is now handled by _scrollToBottomForNavigation with aggressive retries

            // CRITICAL FIX: Always mark messages as read when we receive messages
            // This ensures read status is updated regardless of whether it's initial load or updates
            debugPrint(
                '🔍 STREAM DEBUG: About to call _markMessagesAsRead() for ${messages.length} messages');
            _markMessagesAsRead();
            debugPrint(
                '🔍 STREAM DEBUG: Called _markMessagesAsRead() successfully');
          }
        },
        onError: (error) {
          debugPrint('❌ Error in optimistic messages stream: $error');
        },
      );

      // Server messages are now routed through optimistic UI automatically
      // No need for separate server messages stream subscription
      // All message updates (real-time, server confirmations, etc.) go through optimistic UI

      // New messages are now automatically handled through optimistic UI
      // Real-time updates from Supabase are routed through optimistic UI service
      // No need for separate new message stream subscription

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

      // CRITICAL FIX: Fallback mechanism to ensure markMessagesAsRead is called
      // In case the stream doesn't trigger immediately, call it after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _messages.isNotEmpty) {
          debugPrint(
              '🔍 FALLBACK DEBUG: Calling _markMessagesAsRead() as fallback for ${_messages.length} messages');
          _markMessagesAsRead();
        }
      });

      debugPrint('✅ Chat initialization completed successfully');
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
      // Only trigger pagination after initial load is complete
      if (!_isInitialLoadComplete) {
        debugPrint(
            '🔄 SCROLL DEBUG: Skipping pagination - initial load not complete');
        return;
      }

      // Load more messages when scrolled to top
      if (_scrollController.position.pixels <= 100 &&
          !_isLoadingMore &&
          _hasMoreMessages) {
        debugPrint(
            '🔄 SCROLL DEBUG: User scrolled to top, triggering pagination');
        _loadMoreMessages();
      }
    });
  }

  /// Load more messages (pagination)
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    debugPrint(
        '🔄 PAGINATION DEBUG: Starting to load more messages, setting _isLoadingMore = true');
    setState(() {
      _isLoadingMore = true;
    });

    try {
      // TODO: Implement pagination in conversation service
      // For now, we'll just mark as no more messages
      debugPrint(
          '🔄 PAGINATION DEBUG: Pagination not implemented, setting _isLoadingMore = false');
      setState(() {
        _hasMoreMessages = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      debugPrint(
          '❌ PAGINATION DEBUG: Error occurred, setting _isLoadingMore = false');
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

  /// Check if we should auto-scroll for new messages
  bool _shouldAutoScroll(List<Message> messages) {
    if (messages.isEmpty) return false;

    // Auto-scroll if the newest message is from current user
    final newestMessage = messages.last;
    return newestMessage.senderId == _currentUserId;
  }

  /// Scroll to bottom specifically for navigation (ensures it reaches the very bottom)
  void _scrollToBottomForNavigation() {
    debugPrint('🔄 SCROLL DEBUG: _scrollToBottomForNavigation called');

    // Mark navigation as complete and scrolling as done
    _isNavigationEntry = false;
    _hasScrolledToBottomOnce = true;

    if (!_scrollController.hasClients) {
      debugPrint(
          '🔄 SCROLL DEBUG: No scroll controller clients, scheduling retry');
      // Retry after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _scrollToBottomForNavigation();
      });
      return;
    }

    // Use multiple progressive attempts to ensure we reach the bottom
    _attemptNavigationScrollToBottom(0);
  }

  /// Scroll to bottom of chat with enhanced reliability
  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;

    // CRITICAL FIX: Use a more reliable approach for initial scroll
    // Schedule the scroll for the next frame to ensure ListView is fully built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      // For animated scrolling (new messages), use immediate animation
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent > 0) {
        if (animate) {
          _scrollController.animateTo(
            maxExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(maxExtent);
        }
      }
    });
  }

  /// Attempt to scroll to bottom specifically for navigation with aggressive retries
  void _attemptNavigationScrollToBottom(int attempt) {
    if (!mounted || !_scrollController.hasClients) return;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final currentPosition = _scrollController.position.pixels;

    debugPrint(
        '🔄 SCROLL DEBUG: Navigation scroll attempt $attempt - maxExtent: $maxExtent, current: $currentPosition');

    if (maxExtent > 0) {
      // Jump to the very bottom
      _scrollController.jumpTo(maxExtent);

      // Verify we actually reached the bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          final newPosition = _scrollController.position.pixels;
          final newMaxExtent = _scrollController.position.maxScrollExtent;

          debugPrint(
              '🔄 SCROLL DEBUG: After jump - position: $newPosition, maxExtent: $newMaxExtent');

          // If we're not at the bottom and haven't tried too many times, try again
          if (newPosition < newMaxExtent - 10 && attempt < 8) {
            debugPrint('🔄 SCROLL DEBUG: Not at bottom, retrying...');
            Future.delayed(Duration(milliseconds: 100 + (attempt * 50)), () {
              _attemptNavigationScrollToBottom(attempt + 1);
            });
          } else {
            debugPrint(
                '🔄 SCROLL DEBUG: Navigation scroll completed on attempt $attempt');
          }
        }
      });
    } else if (attempt < 8) {
      // No content yet, try again with increasing delays
      final delay = Duration(milliseconds: 100 + (attempt * 100));
      debugPrint(
          '🔄 SCROLL DEBUG: No content yet, retrying in ${delay.inMilliseconds}ms');
      Future.delayed(delay, () {
        _attemptNavigationScrollToBottom(attempt + 1);
      });
    } else {
      debugPrint(
          '🔄 SCROLL DEBUG: Failed to scroll after 8 attempts - giving up');
    }
  }

  /// Mark messages as read
  void _markMessagesAsRead() {
    debugPrint(
        '🔍 CHAT SCREEN: _markMessagesAsRead() called for conversation: ${widget.conversation.id}');
    _conversationService.markMessagesAsRead(widget.conversation.id);
    debugPrint('🔍 CHAT SCREEN: _markMessagesAsRead() completed');
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

    // CRITICAL FIX: Get keyboard height and handle changes immediately
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    // Handle keyboard changes in real-time during build
    _handleKeyboardChange(keyboardHeight);

    debugPrint('🔄 KEYBOARD DEBUG: keyboardHeight=$keyboardHeight');

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      // CRITICAL FIX: Enable keyboard avoidance to push content up when keyboard appears
      resizeToAvoidBottomInset: true,
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
      body: Stack(
        children: [
          Column(
            children: [
              // Messages list - takes remaining space after input
              Expanded(
                child: _buildMessagesList(),
              ),

              // Typing indicator - clean without wrapper
              TypingIndicator(
                typingUsers: _typingUsers,
                conversation: widget.conversation,
              ),

              // Message input - always at bottom
              UnifiedMessageInput(
                conversation: widget.conversation,
                onSendText: _sendTextMessage,
                onSendImage: _sendImageMessage,
                onTypingChanged: _onTypingChanged,
              ),
            ],
          ),

          // Performance monitor for debugging (only in debug mode)
          if (kDebugMode)
            const Positioned(
              top:
                  60, // Moved down to avoid conflict with other positioned widgets
              right: 10,
              child: PerformanceMonitor(),
            ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    debugPrint(
        '🔍 BUILD DEBUG: _isLoading = $_isLoading, _isLoadingMore = $_isLoadingMore, _messages.length = ${_messages.length}');

    // CRITICAL FIX: Only show loading indicator if we have no messages AND haven't completed initial load
    if (_messages.isEmpty && !_isInitialLoadComplete) {
      debugPrint(
          '🔍 BUILD DEBUG: Showing main loading indicator because no messages and initial load incomplete');
      return const Center(child: LoadingIndicator());
    }

    if (_errorMessage != null) {
      debugPrint('🔍 BUILD DEBUG: Showing error widget: $_errorMessage');
      return Center(
        child: CustomErrorWidget(
          message: _errorMessage!,
          onRetry: _initializeChat,
        ),
      );
    }

    // Show empty state only when no messages and initial load is complete
    if (_messages.isEmpty && _isInitialLoadComplete) {
      debugPrint(
          '🔍 BUILD DEBUG: Showing empty state because _messages.isEmpty and initial load complete');
      return _buildEmptyState();
    }

    debugPrint(
        '🔍 BUILD DEBUG: Showing MessageList with ${_messages.length} messages, isLoadingMore = $_isLoadingMore');
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
