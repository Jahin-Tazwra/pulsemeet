import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:pulsemeet/models/direct_message.dart';
import 'package:pulsemeet/models/chat_message.dart';
import 'package:pulsemeet/models/formatted_text.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/media_service.dart';
import 'package:pulsemeet/services/notification_service.dart';
import 'package:pulsemeet/services/connection_service.dart';

/// Service for managing direct messages between users
class DirectMessageService {
  // Singleton instance
  static final DirectMessageService _instance =
      DirectMessageService._internal();

  factory DirectMessageService() => _instance;

  DirectMessageService._internal() {
    _initService();
  }

  // Supabase client
  final _supabase = Supabase.instance.client;

  // Services
  final _mediaService = MediaService();
  final _notificationService = NotificationService();
  final _connectionService = ConnectionService();

  // UUID generator
  final _uuid = const Uuid();

  // Current user ID
  String? _currentUserId;

  // Stream controllers
  final _conversationsController =
      StreamController<List<Conversation>>.broadcast();
  final _messagesController =
      StreamController<Map<String, List<DirectMessage>>>.broadcast();
  final _newMessageController = StreamController<DirectMessage>.broadcast();
  final _typingStatusController =
      StreamController<Map<String, bool>>.broadcast();

  // Cached data
  final Map<String, List<DirectMessage>> _messagesCache = {};
  final Map<String, bool> _typingStatusCache = {};
  final List<Conversation> _conversations = [];

  // Subscriptions and channels
  StreamSubscription? _messagesSubscription;
  StreamSubscription? _typingSubscription;
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _typingChannel;
  final Map<String, Timer> _refreshTimers = {};

  // Network status
  bool _isOnline = true;

  // Offline message queue
  final List<DirectMessage> _offlineQueue = [];

  /// Stream of conversations
  Stream<List<Conversation>> get conversationsStream =>
      _conversationsController.stream;

  /// Stream of messages for each conversation
  Stream<Map<String, List<DirectMessage>>> get messagesStream =>
      _messagesController.stream;

  /// Stream of new messages
  Stream<DirectMessage> get newMessageStream => _newMessageController.stream;

  /// Stream of typing status for each conversation
  Stream<Map<String, bool>> get typingStatusStream =>
      _typingStatusController.stream;

  /// Initialize the service
  void _initService() {
    // Get current user ID
    _currentUserId = _supabase.auth.currentUser?.id;

    // Listen for auth state changes
    _supabase.auth.onAuthStateChange.listen((data) {
      final newUserId = data.session?.user.id;
      if (newUserId != _currentUserId) {
        _currentUserId = newUserId;
        if (newUserId != null) {
          // Refresh data when user changes
          fetchConversations();
        } else {
          // Clear data when user logs out
          _messagesCache.clear();
          _typingStatusCache.clear();
          _conversations.clear();
          _conversationsController.add([]);
          _messagesController.add({});
          _typingStatusController.add({});
        }
      }
    });

    // Process offline queue when online
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isOnline && _offlineQueue.isNotEmpty) {
        _processOfflineQueue();
      }
    });
  }

  /// Set online status
  void setOnlineStatus(bool isOnline) {
    _isOnline = isOnline;
    if (isOnline && _offlineQueue.isNotEmpty) {
      _processOfflineQueue();
    }
  }

  /// Process offline message queue
  Future<void> _processOfflineQueue() async {
    if (_offlineQueue.isEmpty) return;

    final messagesToProcess = List<DirectMessage>.from(_offlineQueue);
    _offlineQueue.clear();

    for (final message in messagesToProcess) {
      try {
        await _sendMessageToServer(message);
      } catch (e) {
        // If sending fails, add back to queue
        _offlineQueue.add(message);
      }
    }
  }

  /// Add message to offline queue
  void _addToOfflineQueue(DirectMessage message) {
    _offlineQueue.add(message);

    // Add to local cache immediately
    final otherUserId = message.isFromCurrentUser(_currentUserId!)
        ? message.receiverId
        : message.senderId;

    if (!_messagesCache.containsKey(otherUserId)) {
      _messagesCache[otherUserId] = [];
    }

    _messagesCache[otherUserId]!.add(message);
    _messagesController.add(_messagesCache);
  }

  /// Send message to server
  Future<DirectMessage> _sendMessageToServer(DirectMessage message) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      final response = await _supabase
          .from('direct_messages')
          .insert({
            'id': message.id,
            'sender_id': message.senderId,
            'receiver_id': message.receiverId,
            'message_type': message.messageType,
            'content': message.content,
            'is_formatted': message.isFormatted,
            'created_at': message.createdAt.toIso8601String(),
            'updated_at': message.updatedAt.toIso8601String(),
            'media_data': message.mediaData?.toJson(),
            'location_data': message.locationData?.toJson(),
            'reply_to_id': message.replyToId,
            'status': 'sent',
          })
          .select()
          .single();

      return DirectMessage.fromJson(response);
    } catch (e) {
      debugPrint('Error sending message to server: $e');
      rethrow;
    }
  }

  /// Fetch conversations
  Future<List<Conversation>> fetchConversations() async {
    if (_currentUserId == null) return [];

    try {
      // Get all connections
      final connections = await _connectionService.fetchConnections();

      // Create a list of user IDs from connections
      final userIds =
          connections.map((c) => c.getOtherUserId(_currentUserId!)).toList();

      // If no connections, return empty list
      if (userIds.isEmpty) {
        _conversations.clear();
        _conversationsController.add([]);
        return [];
      }

      // Get the latest message for each conversation
      final response = await _supabase
          .from('direct_messages')
          .select()
          .or('and(sender_id.eq.$_currentUserId,receiver_id.in.(${userIds.join(',')})),and(receiver_id.eq.$_currentUserId,sender_id.in.(${userIds.join(',')}))')
          .order('created_at', ascending: false);

      // Group messages by conversation
      final Map<String, DirectMessage> latestMessages = {};

      for (final item in response) {
        final message = DirectMessage.fromJson(item);
        final otherUserId = message.senderId == _currentUserId
            ? message.receiverId
            : message.senderId;

        if (!latestMessages.containsKey(otherUserId)) {
          latestMessages[otherUserId] = message;
        }
      }

      // Create conversations
      final List<Conversation> conversations = [];

      for (final connection in connections) {
        final otherUserId = connection.getOtherUserId(_currentUserId!);
        final otherUserProfile =
            connection.getOtherUserProfile(_currentUserId!);

        if (otherUserProfile != null) {
          final latestMessage = latestMessages[otherUserId];

          conversations.add(Conversation(
            userId: otherUserId,
            profile: otherUserProfile,
            latestMessage: latestMessage,
            unreadCount: 0, // Will be updated later
          ));
        }
      }

      // Sort conversations by latest message time
      conversations.sort((a, b) {
        if (a.latestMessage == null && b.latestMessage == null) return 0;
        if (a.latestMessage == null) return 1;
        if (b.latestMessage == null) return -1;
        return b.latestMessage!.createdAt.compareTo(a.latestMessage!.createdAt);
      });

      _conversations.clear();
      _conversations.addAll(conversations);
      _conversationsController.add(_conversations);

      // Update unread counts
      _updateUnreadCounts();

      return _conversations;
    } catch (e) {
      debugPrint('Error fetching conversations: $e');
      return [];
    }
  }

  /// Update unread message counts
  Future<void> _updateUnreadCounts() async {
    if (_currentUserId == null || _conversations.isEmpty) return;

    try {
      for (int i = 0; i < _conversations.length; i++) {
        final conversation = _conversations[i];

        final response = await _supabase
            .from('direct_messages')
            .select('id', const FetchOptions(count: CountOption.exact))
            .eq('sender_id', conversation.userId)
            .eq('receiver_id', _currentUserId)
            .neq('status', 'read');

        final unreadCount = response.count ?? 0;

        if (unreadCount != conversation.unreadCount) {
          _conversations[i] = conversation.copyWith(unreadCount: unreadCount);
        }
      }

      _conversationsController.add(_conversations);
    } catch (e) {
      debugPrint('Error updating unread counts: $e');
    }
  }

  /// Subscribe to messages for a conversation
  Future<void> subscribeToMessages(String otherUserId) async {
    if (_currentUserId == null) return;

    // Cancel existing subscription
    await _messagesSubscription?.cancel();

    try {
      // Set up real-time subscription
      _messagesChannel = _supabase.channel('direct_messages_$otherUserId');

      _messagesChannel!.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(
          event: 'INSERT',
          schema: 'public',
          table: 'direct_messages',
          filter: 'sender_id=eq.$otherUserId,receiver_id=eq.$_currentUserId',
        ),
        (payload, [ref]) {
          if (payload['new'] != null) {
            final message = DirectMessage.fromJson(payload['new']);
            _handleNewMessage(message);
          }
        },
      );

      _messagesChannel!.subscribe();
      _messagesSubscription = null; // We'll use the channel directly

      // Set up a periodic refresh as a fallback
      final refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (_isOnline) {
          _refreshMessages(otherUserId);
        }
      });

      // Store the timer for cleanup
      _refreshTimers[otherUserId] = refreshTimer;

      // Initial fetch
      await _refreshMessages(otherUserId);
    } catch (e) {
      debugPrint('Error subscribing to messages: $e');
      // Fallback to manual refresh
      await _refreshMessages(otherUserId);
    }
  }

  /// Subscribe to typing status
  Future<void> subscribeToTypingStatus(String otherUserId) async {
    if (_currentUserId == null) return;

    // Cancel existing subscription
    await _typingSubscription?.cancel();

    try {
      // Set up real-time subscription
      _typingChannel = _supabase.channel('typing_status_$otherUserId');

      _typingChannel!.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(
          event: '*',
          schema: 'public',
          table: 'direct_message_typing_status',
          filter: 'user_id=eq.$otherUserId,receiver_id=eq.$_currentUserId',
        ),
        (payload, [ref]) {
          if (payload['new'] != null) {
            final isTyping = payload['new']['is_typing'] as bool;
            _typingStatusCache[otherUserId] = isTyping;
            _typingStatusController.add(_typingStatusCache);
          }
        },
      );

      _typingChannel!.subscribe();
      _typingSubscription = null; // We'll use the channel directly

      // Initial fetch
      await _refreshTypingStatus(otherUserId);
    } catch (e) {
      debugPrint('Error subscribing to typing status: $e');
    }
  }

  /// Refresh messages for a conversation
  Future<void> _refreshMessages(String otherUserId) async {
    if (_currentUserId == null) return;

    try {
      final response = await _supabase
          .from('direct_messages')
          .select()
          .or('and(sender_id.eq.$_currentUserId,receiver_id.eq.$otherUserId),and(receiver_id.eq.$_currentUserId,sender_id.eq.$otherUserId)')
          .order('created_at');

      final messages = response
          .map<DirectMessage>((json) => DirectMessage.fromJson(json))
          .toList();

      _messagesCache[otherUserId] = messages;
      _messagesController.add(_messagesCache);

      // Mark messages as read
      _markMessagesAsRead(otherUserId);
    } catch (e) {
      debugPrint('Error refreshing messages: $e');
    }
  }

  /// Refresh typing status
  Future<void> _refreshTypingStatus(String otherUserId) async {
    if (_currentUserId == null) return;

    try {
      final response = await _supabase
          .from('direct_message_typing_status')
          .select()
          .eq('user_id', otherUserId)
          .eq('receiver_id', _currentUserId);

      if (response.isNotEmpty) {
        final isTyping = response[0]['is_typing'] as bool;
        _typingStatusCache[otherUserId] = isTyping;
        _typingStatusController.add(_typingStatusCache);
      }
    } catch (e) {
      debugPrint('Error refreshing typing status: $e');
    }
  }

  /// Handle new message
  void _handleNewMessage(DirectMessage message) {
    final otherUserId = message.senderId;

    // Add to cache
    if (!_messagesCache.containsKey(otherUserId)) {
      _messagesCache[otherUserId] = [];
    }

    _messagesCache[otherUserId]!.add(message);
    _messagesController.add(_messagesCache);

    // Notify about new message
    _newMessageController.add(message);

    // Update conversation
    _updateConversationWithMessage(message);

    // Mark as read if the conversation is open
    _markMessagesAsRead(otherUserId);
  }

  /// Update conversation with new message
  void _updateConversationWithMessage(DirectMessage message) {
    final otherUserId = message.isFromCurrentUser(_currentUserId!)
        ? message.receiverId
        : message.senderId;

    // Find the conversation
    final index = _conversations.indexWhere((c) => c.userId == otherUserId);

    if (index >= 0) {
      // Update existing conversation
      final conversation = _conversations[index];
      final unreadCount = message.isFromCurrentUser(_currentUserId!)
          ? conversation.unreadCount
          : conversation.unreadCount + 1;

      _conversations[index] = conversation.copyWith(
        latestMessage: message,
        unreadCount: unreadCount,
      );

      // Move to top if not already
      if (index > 0) {
        final updatedConversation = _conversations.removeAt(index);
        _conversations.insert(0, updatedConversation);
      }
    } else {
      // Create new conversation if needed
      // This should rarely happen as we should have all conversations from connections
      // But just in case, we'll handle it
      _connectionService.fetchConnections().then((_) {
        fetchConversations();
      });
    }

    _conversationsController.add(_conversations);
  }

  /// Mark messages as read
  Future<void> _markMessagesAsRead(String otherUserId) async {
    if (_currentUserId == null) return;

    try {
      await _supabase
          .from('direct_messages')
          .update({'status': 'read'})
          .eq('sender_id', otherUserId)
          .eq('receiver_id', _currentUserId)
          .neq('status', 'read');

      // Update unread count in conversation
      final index = _conversations.indexWhere((c) => c.userId == otherUserId);
      if (index >= 0) {
        _conversations[index] = _conversations[index].copyWith(unreadCount: 0);
        _conversationsController.add(_conversations);
      }
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  /// Set typing status
  Future<void> setTypingStatus(String receiverId, bool isTyping) async {
    if (_currentUserId == null) return;

    try {
      await _supabase.from('direct_message_typing_status').upsert({
        'user_id': _currentUserId,
        'receiver_id': receiverId,
        'is_typing': isTyping,
        'last_updated': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error setting typing status: $e');
    }
  }

  /// Send a text message
  Future<DirectMessage?> sendTextMessage(
    String receiverId,
    String content, {
    bool isFormatted = false,
    String? replyToId,
  }) async {
    if (_currentUserId == null) return null;

    final String messageId = _uuid.v4();
    final DateTime now = DateTime.now();

    final DirectMessage message = DirectMessage(
      id: messageId,
      senderId: _currentUserId!,
      receiverId: receiverId,
      messageType: 'text',
      content: content,
      createdAt: now,
      updatedAt: now,
      isFormatted: isFormatted,
      replyToId: replyToId,
      status: _isOnline ? MessageStatus.sending : MessageStatus.failed,
    );

    // If offline, add to queue and return
    if (!_isOnline) {
      final offlineMessage = message.copyWith(isOffline: true);
      _addToOfflineQueue(offlineMessage);
      return offlineMessage;
    }

    try {
      // Add optimistic message to stream immediately
      _handleNewMessage(message);

      // Send message to server
      final sentMessage = await _sendMessageToServer(message);

      // Process mentions if the message contains any
      if (content.contains('@')) {
        // Check if the message has mentions
        final formattedText = FormattedText.fromString(content);
        if (formattedText.segments
            .any((s) => s.type == FormattedSegmentType.mention)) {
          // Convert to formatted text if it contains mentions
          if (!isFormatted) {
            // Update the message to mark it as formatted
            await _supabase.from('direct_messages').update({
              'is_formatted': true,
              'content': formattedText.encode(),
            }).eq('id', messageId);
          }
        }
      }

      // Send notification
      _notificationService.sendDirectMessageNotification(
        receiverId,
        content,
        _currentUserId!,
      );

      return sentMessage;
    } catch (e) {
      debugPrint('Error sending text message: $e');

      // If sending fails, add to offline queue
      final offlineMessage =
          message.copyWith(isOffline: true, status: MessageStatus.failed);
      _addToOfflineQueue(offlineMessage);

      return offlineMessage;
    }
  }

  /// Send an image message
  Future<DirectMessage?> sendImageMessage(
    String receiverId,
    File image, {
    String? caption,
    String? replyToId,
  }) async {
    if (_currentUserId == null) return null;

    try {
      // Upload image
      await _mediaService.uploadMedia(
        image,
        'direct_messages_${_currentUserId}_$receiverId',
      );

      // Create message content
      final content = caption ?? 'Image';

      // Send message
      return await sendTextMessage(
        receiverId,
        content,
        isFormatted: false,
        replyToId: replyToId,
      );
    } catch (e) {
      debugPrint('Error sending image message: $e');
      return null;
    }
  }

  /// Get messages for a conversation
  List<DirectMessage> getMessages(String otherUserId) {
    return _messagesCache[otherUserId] ?? [];
  }

  /// Get typing status for a conversation
  bool isUserTyping(String userId) {
    return _typingStatusCache[userId] ?? false;
  }

  /// Dispose resources
  void dispose() {
    _conversationsController.close();
    _messagesController.close();
    _newMessageController.close();
    _typingStatusController.close();

    // Unsubscribe from channels
    _messagesChannel?.unsubscribe();
    _typingChannel?.unsubscribe();

    // Cancel all refresh timers
    for (final timer in _refreshTimers.values) {
      timer.cancel();
    }
    _refreshTimers.clear();
  }
}

/// Model class for a conversation
class Conversation {
  final String userId;
  final Profile profile;
  final DirectMessage? latestMessage;
  final int unreadCount;

  Conversation({
    required this.userId,
    required this.profile,
    this.latestMessage,
    this.unreadCount = 0,
  });

  /// Create a copy of Conversation with updated fields
  Conversation copyWith({
    String? userId,
    Profile? profile,
    DirectMessage? latestMessage,
    int? unreadCount,
  }) {
    return Conversation(
      userId: userId ?? this.userId,
      profile: profile ?? this.profile,
      latestMessage: latestMessage ?? this.latestMessage,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
