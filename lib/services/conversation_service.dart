import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/media_service.dart';
import 'package:pulsemeet/services/location_service.dart';
import 'package:pulsemeet/services/audio_service.dart';
import 'package:pulsemeet/services/notification_service.dart';
import 'package:pulsemeet/services/unified_encryption_service.dart';
import 'package:pulsemeet/services/enhanced_encryption_service.dart';
import 'package:pulsemeet/services/key_management_service.dart';

/// Unified service for handling all conversation and messaging functionality
class ConversationService {
  static final ConversationService _instance = ConversationService._internal();

  factory ConversationService() => _instance;

  ConversationService._internal() {
    _initService();
  }

  final SupabaseClient _supabase = Supabase.instance.client;
  final MediaService _mediaService = MediaService();
  final LocationService _locationService = LocationService();
  final AudioService _audioService = AudioService();
  final NotificationService _notificationService = NotificationService();
  final UnifiedEncryptionService _encryptionService =
      UnifiedEncryptionService();
  final EnhancedEncryptionService _enhancedEncryptionService =
      EnhancedEncryptionService();
  final KeyManagementService _keyManagementService = KeyManagementService();
  final Uuid _uuid = const Uuid();

  // Stream controllers
  final StreamController<List<Conversation>> _conversationsController =
      StreamController<List<Conversation>>.broadcast();
  final StreamController<List<Message>> _messagesController =
      StreamController<List<Message>>.broadcast();
  final StreamController<Message> _newMessageController =
      StreamController<Message>.broadcast();
  final StreamController<String> _messageStatusController =
      StreamController<String>.broadcast();
  final StreamController<Map<String, List<String>>> _typingStatusController =
      StreamController<Map<String, List<String>>>.broadcast();

  // Subscriptions
  StreamSubscription<List<Map<String, dynamic>>>? _conversationsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _messagesSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _typingSubscription;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // State
  bool _isInitialized = false;
  bool _isOnline = true;
  String? _currentConversationId;
  String? _currentUserId;
  List<Message> _offlineQueue = [];

  // Caches for performance
  final Map<String, List<Conversation>> _conversationsCache = {};
  final Map<String, List<Message>> _messagesCache = {};
  final Map<String, List<ConversationParticipant>> _participantsCache = {};
  final Map<String, DateTime> _lastFetchTime = {};

  // Getters
  Stream<List<Conversation>> get conversationsStream =>
      _conversationsController.stream;
  Stream<List<Message>> get messagesStream => _messagesController.stream;
  Stream<Message> get newMessageStream => _newMessageController.stream;
  Stream<String> get messageStatusStream => _messageStatusController.stream;
  Stream<Map<String, List<String>>> get typingStatusStream =>
      _typingStatusController.stream;

  /// Initialize the service
  Future<void> _initService() async {
    if (_isInitialized) return;

    debugPrint('🚀 Initializing ConversationService');

    // Initialize encryption services
    await _initializeEncryption();

    // Load offline queue
    await _loadOfflineQueue();

    // Listen for connectivity changes
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      final bool wasOnline = _isOnline;
      _isOnline = result != ConnectivityResult.none;

      debugPrint(
          '📶 Connectivity changed: ${_isOnline ? 'Online' : 'Offline'}');

      // If we just came back online, process the offline queue
      if (!wasOnline && _isOnline) {
        _processOfflineQueue();
      }
    });

    // Check initial connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    _isOnline = connectivityResult != ConnectivityResult.none;

    // Get current user
    _currentUserId = _supabase.auth.currentUser?.id;
    debugPrint('👤 Current user ID: $_currentUserId');
    debugPrint('🌐 Online status: $_isOnline');
    debugPrint('🔗 Supabase URL: ${_supabase.supabaseUrl}');

    _isInitialized = true;
    debugPrint('✅ ConversationService initialized');
  }

  /// Initialize encryption services
  Future<void> _initializeEncryption() async {
    try {
      await _encryptionService.initialize();
      await _keyManagementService.initialize();
      debugPrint('🔐 Encryption services initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize encryption: $e');
    }
  }

  /// Load offline queue from local storage
  Future<void> _loadOfflineQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString('offline_message_queue');
      if (queueJson != null) {
        final List<dynamic> queueData = jsonDecode(queueJson);
        _offlineQueue =
            queueData.map((data) => Message.fromJson(data)).toList();
        debugPrint('📱 Loaded ${_offlineQueue.length} offline messages');
      }
    } catch (e) {
      debugPrint('❌ Error loading offline queue: $e');
    }
  }

  /// Save offline queue to local storage
  Future<void> _saveOfflineQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson =
          jsonEncode(_offlineQueue.map((msg) => msg.toJson()).toList());
      await prefs.setString('offline_message_queue', queueJson);
    } catch (e) {
      debugPrint('❌ Error saving offline queue: $e');
    }
  }

  /// Process offline queue when coming back online
  Future<void> _processOfflineQueue() async {
    if (_offlineQueue.isEmpty) return;

    debugPrint('📤 Processing ${_offlineQueue.length} offline messages');

    final List<Message> processedMessages = [];

    for (final message in _offlineQueue) {
      try {
        Message? sentMessage;

        switch (message.messageType) {
          case MessageType.text:
            sentMessage = await sendTextMessage(
              message.conversationId,
              message.content,
              isFormatted: message.isFormatted,
              replyToId: message.replyToId,
            );
            break;
          case MessageType.image:
            // For offline images, we need to handle file upload
            if (message.mediaData?.url.startsWith('file://') == true) {
              final file =
                  File(message.mediaData!.url.replaceFirst('file://', ''));
              if (await file.exists()) {
                sentMessage = await sendImageMessage(
                  message.conversationId,
                  file,
                  caption: message.content,
                  replyToId: message.replyToId,
                );
              }
            }
            break;
          // Add other message types as needed
          default:
            debugPrint(
                '⚠️ Unsupported offline message type: ${message.messageType}');
        }

        if (sentMessage != null) {
          processedMessages.add(message);
        }
      } catch (e) {
        debugPrint('❌ Failed to process offline message ${message.id}: $e');
      }
    }

    // Remove processed messages from queue
    for (final processed in processedMessages) {
      _offlineQueue.remove(processed);
    }

    await _saveOfflineQueue();
    debugPrint('✅ Processed ${processedMessages.length} offline messages');
  }

  /// Add message to offline queue
  void _addToOfflineQueue(Message message) {
    _offlineQueue.add(message);
    _saveOfflineQueue();
    debugPrint('📱 Added message to offline queue: ${message.id}');
  }

  /// Ensure user is authenticated, retry if needed
  Future<void> _ensureAuthenticated() async {
    // If we already have a user ID, we're good
    if (_currentUserId != null) {
      debugPrint('✅ User already authenticated: $_currentUserId');
      return;
    }

    debugPrint('🔄 Checking authentication status...');

    // Check current auth state
    _currentUserId = _supabase.auth.currentUser?.id;

    if (_currentUserId != null) {
      debugPrint('✅ Authentication restored: $_currentUserId');
      return;
    }

    // Wait a bit for auth to initialize after hot restart
    debugPrint('⏳ Waiting for authentication to initialize...');
    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      _currentUserId = _supabase.auth.currentUser?.id;

      if (_currentUserId != null) {
        debugPrint(
            '✅ Authentication available after ${(i + 1) * 500}ms: $_currentUserId');
        return;
      }
    }

    debugPrint('❌ Authentication not available after 5 seconds');
  }

  /// Subscribe to conversations for current user
  Future<void> subscribeToConversations() async {
    // Check if user is authenticated, retry if not
    await _ensureAuthenticated();

    if (_currentUserId == null) {
      debugPrint(
          '❌ Cannot subscribe to conversations: No current user after retry');
      _conversationsController.addError('No authenticated user');
      return;
    }

    try {
      debugPrint('🔔 Subscribing to conversations for user: $_currentUserId');

      // Cancel existing subscription if any
      await _conversationsSubscription?.cancel();

      // Load initial conversations first and ensure they're emitted
      await _loadConversations();

      // Give a small delay to ensure initial load completes
      await Future.delayed(const Duration(milliseconds: 100));

      // Subscribe to conversations table for real-time updates
      // Note: We'll filter the updates in the handler
      _conversationsSubscription = _supabase
          .from('conversations')
          .stream(primaryKey: ['id'])
          .order('last_message_at', ascending: false)
          .listen((List<Map<String, dynamic>> data) async {
            debugPrint(
                '📡 Received real-time conversation update: ${data.length} items');
            await _handleConversationsStreamUpdate(data);
          }, onError: (error) {
            debugPrint('❌ Error in conversations stream: $error');
            _conversationsController.addError(error);
          });

      debugPrint('✅ Successfully subscribed to conversations');
    } catch (e) {
      debugPrint('❌ Error subscribing to conversations: $e');
      _conversationsController.addError(e);
    }
  }

  /// Handle conversations stream update with user participation filtering
  Future<void> _handleConversationsStreamUpdate(
      List<Map<String, dynamic>> data) async {
    try {
      debugPrint(
          '📨 Received conversations stream update: ${data.length} conversations');

      // Filter conversations to only include those where user is a participant
      final List<Map<String, dynamic>> userConversations = [];

      for (final conversationData in data) {
        try {
          final conversationId = conversationData['id']?.toString();
          if (conversationId == null) {
            debugPrint('⚠️ Skipping conversation with null ID');
            continue;
          }

          // Check if user is a participant in this conversation
          final isParticipant = await _isUserParticipant(conversationId);
          if (isParticipant) {
            userConversations.add(conversationData);
          }
        } catch (e) {
          debugPrint('❌ Error processing conversation in stream update: $e');
          continue;
        }
      }

      if (userConversations.isEmpty) {
        debugPrint(
            '📭 No user conversations found in stream update - keeping existing conversations');
        // Don't clear existing conversations, just skip this update
        return;
      }

      // Process the filtered conversations with proper mapping for real-time data
      await _handleRealTimeConversationsUpdate(userConversations);
    } catch (e) {
      debugPrint('❌ Error handling conversations stream update: $e');
      // Don't clear conversations on error, just log it
      debugPrint(
          '🔄 Keeping existing conversations due to stream update error');
    }
  }

  /// Handle real-time conversations update with proper field mapping
  Future<void> _handleRealTimeConversationsUpdate(
      List<Map<String, dynamic>> data) async {
    try {
      debugPrint(
          '📡 Processing real-time conversations update: ${data.length} conversations');

      // Map raw database format to expected format
      final List<Map<String, dynamic>> mappedData = [];

      for (final rawData in data) {
        try {
          debugPrint('📝 Mapping real-time conversation: ${rawData['id']}');

          // Validate required fields first
          final conversationId = rawData['id']?.toString();
          if (conversationId == null || conversationId.isEmpty) {
            debugPrint('⚠️ Skipping conversation with null/empty ID');
            continue;
          }

          // Map snake_case database fields to camelCase model fields with null safety
          final mappedConversation = {
            'id': conversationId, // Already validated as non-null
            'type': rawData['type']?.toString() ?? 'direct_message',
            'title': rawData['title']?.toString(),
            'description': rawData['description']?.toString(),
            'avatarUrl': rawData['avatar_url']?.toString(),
            'pulseId': rawData['pulse_id']?.toString(),
            'createdBy': rawData['created_by']?.toString(),
            'createdAt': rawData['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
            'updatedAt': rawData['updated_at']?.toString() ??
                DateTime.now().toIso8601String(),
            'lastMessageAt': rawData['last_message_at']?.toString(),
            'isArchived': rawData['is_archived'] ?? false,
            'isMuted': rawData['is_muted'] ?? false,
            'settings': rawData['settings'] ?? {},
            'encryptionEnabled': rawData['encryption_enabled'] ?? true,
            'encryptionKeyId': rawData['encryption_key_id']?.toString(),
          };

          mappedData.add(mappedConversation);
          debugPrint(
              '✅ Successfully mapped real-time conversation: ${mappedConversation['id']}');
        } catch (e) {
          debugPrint('❌ Error mapping real-time conversation: $e');
          debugPrint('📊 Raw data: $rawData');
          continue;
        }
      }

      if (mappedData.isEmpty) {
        debugPrint(
            '⚠️ No conversations successfully mapped from real-time update');
        return;
      }

      // Process the mapped conversations with merge strategy for real-time updates
      await _handleConversationsUpdate(mappedData, isRealTimeUpdate: true);
    } catch (e) {
      debugPrint('❌ Error handling real-time conversations update: $e');
      // Don't clear existing conversations on error
    }
  }

  /// Handle conversations update from RPC or mapped real-time data
  Future<void> _handleConversationsUpdate(
    List<Map<String, dynamic>> data, {
    bool isRealTimeUpdate = false,
  }) async {
    try {
      debugPrint(
          '📨 Processing conversations update: ${data.length} conversations');

      final List<Conversation> conversations = [];

      for (final conversationData in data) {
        try {
          debugPrint(
              '📝 Creating conversation from: ${conversationData['id']}');

          // Validate required fields before creating conversation
          if (conversationData['id'] == null) {
            debugPrint('⚠️ Skipping conversation with null ID');
            continue;
          }

          if (conversationData['createdAt'] == null) {
            debugPrint(
                '⚠️ Adding default createdAt for conversation ${conversationData['id']}');
            conversationData['createdAt'] = DateTime.now().toIso8601String();
          }

          if (conversationData['updatedAt'] == null) {
            debugPrint(
                '⚠️ Adding default updatedAt for conversation ${conversationData['id']}');
            conversationData['updatedAt'] = DateTime.now().toIso8601String();
          }

          final conversation = Conversation.fromJson(conversationData);

          // Load participants for each conversation
          final participants =
              await _getConversationParticipants(conversation.id);

          debugPrint(
              '👥 Found ${participants.length} participants for conversation ${conversation.id}');

          // For conversations loaded via get_user_conversations, we already know the user is a participant
          // But for real-time updates, we need to check
          if (participants.isEmpty) {
            debugPrint(
                '⚠️ No participants found for conversation ${conversation.id}');
            continue;
          }

          final isParticipant = participants
              .any((participant) => participant.userId == _currentUserId);

          if (!isParticipant) {
            debugPrint(
                '⚠️ Skipping conversation ${conversation.id} - user not a participant');
            continue;
          }

          // Calculate unread count (with timeout to prevent hanging)
          int unreadCount = 0;
          try {
            unreadCount = await _getUnreadMessageCount(conversation.id)
                .timeout(const Duration(seconds: 3), onTimeout: () => 0);
          } catch (e) {
            debugPrint(
                '⚠️ Failed to get unread count for ${conversation.id}: $e');
          }

          // Get last message preview (with timeout to prevent hanging)
          Message? lastMessage;
          try {
            lastMessage = await _getLastMessage(conversation.id)
                .timeout(const Duration(seconds: 3), onTimeout: () => null);
          } catch (e) {
            debugPrint(
                '⚠️ Failed to get last message for ${conversation.id}: $e');
          }

          conversations.add(conversation.copyWith(
            participants: participants,
            unreadCount: unreadCount,
            lastMessagePreview: lastMessage?.getDisplayContent(),
          ));

          debugPrint(
              '✅ Successfully processed conversation ${conversation.id}');
        } catch (e) {
          debugPrint('❌ Error processing conversation: $e');
          // Continue with other conversations instead of failing completely
          continue;
        }
      }

      debugPrint('📤 Emitting ${conversations.length} conversations to stream');

      // Handle real-time updates with merge strategy
      if (isRealTimeUpdate && conversations.isNotEmpty) {
        // Merge with existing conversations instead of replacing
        final existingConversations =
            _conversationsCache[_currentUserId!] ?? [];
        final mergedConversations =
            _mergeConversations(existingConversations, conversations);

        _conversationsCache[_currentUserId!] = mergedConversations;
        _conversationsController.add(mergedConversations);
        debugPrint('✅ Real-time conversations merged and emitted successfully');
      } else if (conversations.isNotEmpty ||
          _conversationsCache[_currentUserId!] == null) {
        // For initial load or when we have conversations
        _conversationsCache[_currentUserId!] = conversations;
        _conversationsController.add(conversations);
        debugPrint('✅ Conversations emitted successfully');
      } else {
        debugPrint(
            '🔄 Skipping empty conversation update to preserve existing conversations');
      }
    } catch (e) {
      debugPrint('❌ Error handling conversations update: $e');
      debugPrint('📊 Error details: ${e.toString()}');

      // Only emit empty list if we don't have cached conversations (initial load failure)
      if (_conversationsCache[_currentUserId!] == null) {
        debugPrint(
            '📭 No cached conversations, emitting empty list for initial load failure');
        _conversationsController.add([]);
      } else {
        debugPrint(
            '🔄 Keeping existing cached conversations due to update error');
      }

      _conversationsController.addError(e);
    }
  }

  /// Merge existing conversations with new ones from real-time updates
  List<Conversation> _mergeConversations(
      List<Conversation> existing, List<Conversation> updates) {
    try {
      debugPrint(
          '🔄 Merging ${existing.length} existing with ${updates.length} updates');

      // Create a map of existing conversations by ID for quick lookup
      final Map<String, Conversation> existingMap = {
        for (final conv in existing) conv.id: conv
      };

      // Update or add conversations from the updates
      for (final updatedConv in updates) {
        existingMap[updatedConv.id] = updatedConv;
      }

      // Convert back to list and sort by last message time
      final mergedList = existingMap.values.toList();
      mergedList.sort((a, b) {
        final aTime = a.lastMessageAt ?? a.updatedAt;
        final bTime = b.lastMessageAt ?? b.updatedAt;
        return bTime.compareTo(aTime);
      });

      debugPrint('✅ Merged result: ${mergedList.length} conversations');
      return mergedList;
    } catch (e) {
      debugPrint('❌ Error merging conversations: $e');
      // Return existing conversations if merge fails
      return existing;
    }
  }

  /// Load conversations for current user
  Future<void> _loadConversations() async {
    // Ensure user is authenticated before loading
    await _ensureAuthenticated();

    if (_currentUserId == null) {
      debugPrint('❌ Cannot load conversations: No current user after retry');
      _conversationsController.add([]);
      return;
    }

    try {
      debugPrint('📥 Loading conversations for user: $_currentUserId');

      // Use the new function that avoids RLS recursion
      final response = await _supabase
          .rpc('get_user_conversations')
          .timeout(const Duration(seconds: 15));

      debugPrint('📊 RPC response type: ${response.runtimeType}');
      debugPrint('📊 RPC response: $response');

      final List<dynamic> responseList = response is List ? response : [];
      debugPrint(
          '📊 Loaded ${responseList.length} conversations from database');

      if (responseList.isEmpty) {
        // User has no conversations, send empty list
        _conversationsCache[_currentUserId!] = [];
        _conversationsController.add([]);
        debugPrint('✅ No conversations found for user - emitted empty list');
        return;
      }

      // Convert the response to the expected format with proper field mapping
      final conversationsData = responseList.map((item) {
        try {
          final data = Map<String, dynamic>.from(item);
          debugPrint('📝 Processing conversation: ${data['id']}');

          // Map snake_case database fields to camelCase model fields
          return {
            'id': data['id']?.toString(),
            'type': data['type']?.toString() ?? 'direct_message',
            'title': data['title']?.toString(),
            'description': data['description']?.toString(),
            'avatarUrl': data['avatar_url']?.toString(),
            'pulseId': data['pulse_id']?.toString(),
            'createdBy': data['created_by']?.toString(),
            'createdAt': data['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
            'updatedAt': data['updated_at']?.toString() ??
                DateTime.now().toIso8601String(),
            'lastMessageAt': data['last_message_at']?.toString(),
            'isArchived': data['is_archived'] ?? false,
            'isMuted': data['is_muted'] ?? false,
            'settings': data['settings'] ?? {},
            'encryptionEnabled': data['encryption_enabled'] ?? true,
            'encryptionKeyId': data['encryption_key_id']?.toString(),
          };
        } catch (e) {
          debugPrint('❌ Error mapping conversation data: $e');
          // Return a minimal valid conversation object
          return {
            'id': item['id']?.toString() ?? _uuid.v4(),
            'type': 'direct_message',
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
            'isArchived': false,
            'isMuted': false,
            'settings': {},
            'encryptionEnabled': true,
          };
        }
      }).toList();

      debugPrint(
          '📝 Mapped ${conversationsData.length} conversations, processing...');
      await _handleConversationsUpdate(conversationsData);
      debugPrint('✅ Conversations loaded and emitted successfully');
    } catch (e) {
      debugPrint('❌ Error loading conversations: $e');
      // Send empty list on error so UI doesn't hang
      _conversationsCache[_currentUserId!] = [];
      _conversationsController.add([]);
      _conversationsController.addError(e);
    }
  }

  /// Check if current user is a participant in a conversation
  Future<bool> _isUserParticipant(String conversationId) async {
    if (_currentUserId == null) return false;

    try {
      // Use a simple count query to check participation
      final response = await _supabase.rpc('check_user_participation', params: {
        'conversation_id_param': conversationId,
        'user_id_param': _currentUserId,
      }).timeout(const Duration(seconds: 5));

      return response == true;
    } catch (e) {
      debugPrint('❌ Error checking user participation: $e');
      return false;
    }
  }

  /// Get conversation participants using the new function to avoid RLS recursion
  Future<List<ConversationParticipant>> _getConversationParticipants(
      String conversationId) async {
    try {
      // Check cache first
      if (_participantsCache.containsKey(conversationId)) {
        return _participantsCache[conversationId]!;
      }

      // Use the new function that avoids RLS recursion
      final response =
          await _supabase.rpc('get_user_conversation_participants').timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint(
              '⏰ Timeout getting participants for conversation: $conversationId');
          return <Map<String, dynamic>>[];
        },
      );

      // Filter for the specific conversation
      final conversationParticipants = (response as List<dynamic>)
          .where((data) => data['conversation_id'] == conversationId)
          .toList();

      final participants =
          conversationParticipants.map<ConversationParticipant>((data) {
        return ConversationParticipant.fromJson({
          'id': data['id'],
          'conversationId': data['conversation_id'],
          'userId': data['user_id'],
          'role': data['role'],
          'joinedAt': data['joined_at'],
          'lastReadAt': data['last_read_at'],
          'isMuted': data['is_muted'] ?? false,
          'notificationSettings': data['notification_settings'] ?? {},
          'username': data['username'],
          'displayName': data['display_name'],
          'avatarUrl': data['avatar_url'],
        });
      }).toList();

      _participantsCache[conversationId] = participants;
      return participants;
    } catch (e) {
      debugPrint('❌ Error getting conversation participants: $e');
      return [];
    }
  }

  /// Get unread message count for conversation
  Future<int> _getUnreadMessageCount(String conversationId) async {
    try {
      final participant = await _supabase
          .from('conversation_participants')
          .select('last_read_at')
          .eq('conversation_id', conversationId)
          .eq('user_id', _currentUserId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      if (participant == null) return 0;

      final lastReadAt = participant['last_read_at'] as String?;

      if (lastReadAt == null) {
        // Count all messages if never read
        final response = await _supabase
            .from('messages')
            .select('id', const FetchOptions(count: CountOption.exact))
            .eq('conversation_id', conversationId)
            .neq('sender_id', _currentUserId)
            .timeout(const Duration(seconds: 5), onTimeout: () => []);

        return response.count ?? 0;
      } else {
        // Count messages after last read time
        final response = await _supabase
            .from('messages')
            .select('id', const FetchOptions(count: CountOption.exact))
            .eq('conversation_id', conversationId)
            .neq('sender_id', _currentUserId)
            .gt('created_at', lastReadAt)
            .timeout(const Duration(seconds: 5), onTimeout: () => []);

        return response.count ?? 0;
      }
    } catch (e) {
      debugPrint('❌ Error getting unread count: $e');
      return 0;
    }
  }

  /// Get last message for conversation
  Future<Message?> _getLastMessage(String conversationId) async {
    try {
      final response = await _supabase
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      if (response == null) return null;

      return Message.fromJson(response);
    } catch (e) {
      debugPrint('❌ Error getting last message: $e');
      return null;
    }
  }

  /// Create or get direct message conversation
  Future<Conversation?> createDirectConversation(String otherUserId) async {
    if (_currentUserId == null) {
      debugPrint('❌ Cannot create conversation: No current user');
      return null;
    }

    try {
      debugPrint('💬 Creating direct conversation with user: $otherUserId');

      final response =
          await _supabase.rpc('create_direct_conversation', params: {
        'other_user_id': otherUserId,
      }).timeout(const Duration(seconds: 10));

      debugPrint('📝 RPC response: $response (type: ${response.runtimeType})');

      if (response == null) {
        debugPrint('❌ RPC returned null - user might not be authenticated');
        return null;
      }

      // Handle different response types
      String conversationId;
      if (response is String) {
        conversationId = response;
      } else if (response is Map && response.containsKey('id')) {
        conversationId = response['id'].toString();
      } else {
        conversationId = response.toString();
      }

      debugPrint('📝 Conversation ID: $conversationId');

      // Get the created conversation using our safe function
      final conversationResponse = await _supabase
          .rpc('get_user_conversations')
          .timeout(const Duration(seconds: 10));

      // Find the specific conversation
      final conversationData = (conversationResponse as List).firstWhere(
        (item) => item['id'].toString() == conversationId,
        orElse: () => null,
      );

      if (conversationData == null) {
        debugPrint('❌ Could not find created conversation');
        return null;
      }

      // Map the fields properly
      final mappedData = {
        'id': conversationData['id']?.toString(),
        'type': conversationData['type']?.toString(),
        'title': conversationData['title']?.toString(),
        'description': conversationData['description']?.toString(),
        'avatarUrl': conversationData['avatar_url']?.toString(),
        'pulseId': conversationData['pulse_id']?.toString(),
        'createdBy': conversationData['created_by']?.toString(),
        'createdAt': conversationData['created_at']?.toString() ??
            DateTime.now().toIso8601String(),
        'updatedAt': conversationData['updated_at']?.toString() ??
            DateTime.now().toIso8601String(),
        'lastMessageAt': conversationData['last_message_at']?.toString(),
        'isArchived': conversationData['is_archived'] ?? false,
        'isMuted': conversationData['is_muted'] ?? false,
        'settings': conversationData['settings'] ?? {},
        'encryptionEnabled': conversationData['encryption_enabled'] ?? true,
        'encryptionKeyId': conversationData['encryption_key_id']?.toString(),
      };

      final conversation = Conversation.fromJson(mappedData);

      // Load participants
      final participants = await _getConversationParticipants(conversationId);

      return conversation.copyWith(participants: participants);
    } catch (e) {
      debugPrint('❌ Error creating direct conversation: $e');
      return null;
    }
  }

  /// Create pulse group conversation
  Future<Conversation?> createPulseConversation(String pulseId) async {
    if (_currentUserId == null) return null;

    try {
      debugPrint('👥 Creating pulse conversation for pulse: $pulseId');

      final response =
          await _supabase.rpc('create_pulse_conversation', params: {
        'pulse_id_param': pulseId,
      });

      final conversationId = response as String;

      // Get the created conversation
      final conversationResponse = await _supabase
          .from('conversations')
          .select()
          .eq('id', conversationId)
          .single();

      return Conversation.fromJson(conversationResponse);
    } catch (e) {
      debugPrint('❌ Error creating pulse conversation: $e');
      return null;
    }
  }

  /// Send a text message
  Future<Message?> sendTextMessage(
    String conversationId,
    String content, {
    bool isFormatted = false,
    String? replyToId,
  }) async {
    if (_currentUserId == null) return null;

    final String messageId = _uuid.v4();
    final DateTime now = DateTime.now();

    final Message message = Message(
      id: messageId,
      conversationId: conversationId,
      senderId: _currentUserId!,
      messageType: MessageType.text,
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
      _newMessageController.add(offlineMessage);
      return offlineMessage;
    }

    try {
      // Add optimistic message to stream immediately
      _newMessageController.add(message);

      // Encrypt the message before sending
      Message messageToSend = message;
      try {
        final encryptedMessage =
            await _encryptionService.encryptMessage(message);
        if (encryptedMessage.isEncrypted) {
          messageToSend = encryptedMessage;
          debugPrint('🔐 Message encrypted successfully');
        } else {
          messageToSend = encryptedMessage;
          debugPrint('⚠️ Message encryption failed, sending unencrypted');
        }
      } catch (e) {
        debugPrint('⚠️ Failed to encrypt message, sending unencrypted: $e');
      }

      // Send message to server
      final response = await _supabase
          .from('messages')
          .insert({
            'id': messageId,
            'conversation_id': conversationId,
            'sender_id': _currentUserId,
            'message_type': messageToSend.messageType.name,
            'content': messageToSend.content,
            'created_at': now.toIso8601String(),
            'is_formatted': messageToSend.isFormatted,
            'reply_to_id': replyToId,
            'status': 'sent',
            'is_encrypted': messageToSend.isEncrypted,
            'encryption_metadata': messageToSend.encryptionMetadata,
            'key_version': messageToSend.keyVersion,
          })
          .select()
          .single();

      // Map database response to expected format
      final mappedResponse = {
        'id': response['id'],
        'conversationId': response['conversation_id'],
        'senderId': response['sender_id'],
        'messageType': response['message_type'],
        'content': response['content'],
        'isDeleted': response['is_deleted'] ?? false,
        'isEdited': response['is_edited'] ?? false,
        'createdAt': response['created_at'],
        'updatedAt': response['updated_at'],
        'editedAt': response['edited_at'],
        'expiresAt': response['expires_at'],
        'status': response['status'],
        'replyToId': response['reply_to_id'],
        'forwardFromId': response['forward_from_id'],
        'reactions': response['reactions'] ?? [],
        'mentions': response['mentions'] ?? [],
        'mediaData': response['media_data'],
        'locationData': response['location_data'],
        'callData': response['call_data'],
        'isFormatted': response['is_formatted'] ?? false,
        'isEncrypted': response['is_encrypted'] ?? false,
        'encryptionMetadata': response['encryption_metadata'],
        'keyVersion': response['key_version'] ?? 1,
      };

      final sentMessage = Message.fromJson(mappedResponse);
      _messageStatusController.add(messageId);

      return sentMessage;
    } catch (e) {
      debugPrint('❌ Error sending text message: $e');

      // Add to offline queue if failed
      final failedMessage = message.copyWith(
        status: MessageStatus.failed,
        isOffline: true,
      );
      _addToOfflineQueue(failedMessage);

      return failedMessage;
    }
  }

  /// Send an image message
  Future<Message?> sendImageMessage(
    String conversationId,
    dynamic imageFile, {
    String? caption,
    String? replyToId,
  }) async {
    if (_currentUserId == null) return null;

    final String messageId = _uuid.v4();
    final DateTime now = DateTime.now();

    // Create temporary media data with local file path
    final MediaData tempMediaData = MediaData(
      url: 'file://${imageFile.path}',
      mimeType: 'image/${imageFile.path.split('.').last}',
      size: imageFile.lengthSync(),
      fileName: imageFile.path.split('/').last,
    );

    final Message tempMessage = Message(
      id: messageId,
      conversationId: conversationId,
      senderId: _currentUserId!,
      messageType: MessageType.image,
      content: caption ?? '',
      createdAt: now,
      updatedAt: now,
      status: MessageStatus.sending,
      replyToId: replyToId,
      mediaData: tempMediaData,
    );

    // Add temporary message to stream immediately
    _newMessageController.add(tempMessage);

    // If offline, add to queue and return
    if (!_isOnline) {
      final offlineMessage = tempMessage.copyWith(
        status: MessageStatus.failed,
        isOffline: true,
      );
      _addToOfflineQueue(offlineMessage);
      return offlineMessage;
    }

    try {
      // Upload image with encryption
      final MediaData? uploadedMediaData = await _uploadMediaFile(
        imageFile,
        conversationId,
      );

      if (uploadedMediaData == null) {
        throw Exception('Failed to upload image');
      }

      // Create message with uploaded media data
      final Message messageWithMedia = tempMessage.copyWith(
        mediaData: uploadedMediaData,
      );

      // Encrypt the message
      Message messageToSend = messageWithMedia;
      try {
        messageToSend =
            await _encryptionService.encryptMessage(messageWithMedia);
        debugPrint('🔐 Image message encrypted successfully');
      } catch (e) {
        debugPrint(
            '⚠️ Failed to encrypt image message, sending unencrypted: $e');
      }

      // Send message to server
      final response = await _supabase
          .from('messages')
          .insert({
            'id': messageId,
            'conversation_id': conversationId,
            'sender_id': _currentUserId,
            'message_type': 'image',
            'content': messageToSend.content,
            'created_at': now.toIso8601String(),
            'media_data': jsonEncode(uploadedMediaData.toJson()),
            'reply_to_id': replyToId,
            'status': 'sent',
            'is_encrypted': messageToSend.isEncrypted,
            'encryption_metadata': messageToSend.encryptionMetadata,
            'key_version': messageToSend.keyVersion,
          })
          .select()
          .single();

      // Map database response to expected format
      final mappedResponse = {
        'id': response['id'],
        'conversationId': response['conversation_id'],
        'senderId': response['sender_id'],
        'messageType': response['message_type'],
        'content': response['content'],
        'isDeleted': response['is_deleted'] ?? false,
        'isEdited': response['is_edited'] ?? false,
        'createdAt': response['created_at'],
        'updatedAt': response['updated_at'],
        'editedAt': response['edited_at'],
        'expiresAt': response['expires_at'],
        'status': response['status'],
        'replyToId': response['reply_to_id'],
        'forwardFromId': response['forward_from_id'],
        'reactions': response['reactions'] ?? [],
        'mentions': response['mentions'] ?? [],
        'mediaData': response['media_data'],
        'locationData': response['location_data'],
        'callData': response['call_data'],
        'isFormatted': response['is_formatted'] ?? false,
        'isEncrypted': response['is_encrypted'] ?? false,
        'encryptionMetadata': response['encryption_metadata'],
        'keyVersion': response['key_version'] ?? 1,
      };

      final sentMessage = Message.fromJson(mappedResponse);
      _messageStatusController.add(messageId);

      return sentMessage;
    } catch (e) {
      debugPrint('❌ Error sending image message: $e');

      // Add to offline queue if failed
      final failedMessage = tempMessage.copyWith(
        status: MessageStatus.failed,
        isOffline: true,
      );
      _addToOfflineQueue(failedMessage);

      return failedMessage;
    }
  }

  /// Subscribe to messages for a specific conversation
  Future<void> subscribeToMessages(String conversationId) async {
    if (_currentUserId == null) return;

    try {
      debugPrint(
          '🔔 Subscribing to messages for conversation: $conversationId');
      _currentConversationId = conversationId;

      // Subscribe to messages real-time updates
      _messagesSubscription = _supabase
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true)
          .listen((List<Map<String, dynamic>> data) async {
            await _handleMessagesUpdate(conversationId, data);
          }, onError: (error) {
            debugPrint('❌ Error in messages stream: $error');
          });

      // Load initial messages
      await _loadMessages(conversationId);
    } catch (e) {
      debugPrint('❌ Error subscribing to messages: $e');
    }
  }

  /// Handle messages update from real-time stream
  Future<void> _handleMessagesUpdate(
      String conversationId, List<Map<String, dynamic>> data) async {
    try {
      debugPrint('📨 Received messages update: ${data.length} messages');

      final List<Message> messages = [];

      for (final messageData in data) {
        // Map database response to expected format
        final mappedMessageData = {
          'id': messageData['id'],
          'conversationId': messageData['conversation_id'],
          'senderId': messageData['sender_id'],
          'messageType': messageData['message_type'],
          'content': messageData['content'],
          'isDeleted': messageData['is_deleted'] ?? false,
          'isEdited': messageData['is_edited'] ?? false,
          'createdAt': messageData['created_at'],
          'updatedAt': messageData['updated_at'],
          'editedAt': messageData['edited_at'],
          'expiresAt': messageData['expires_at'],
          'status': messageData['status'],
          'replyToId': messageData['reply_to_id'],
          'forwardFromId': messageData['forward_from_id'],
          'reactions': messageData['reactions'] ?? [],
          'mentions': messageData['mentions'] ?? [],
          'mediaData': messageData['media_data'],
          'locationData': messageData['location_data'],
          'callData': messageData['call_data'],
          'isFormatted': messageData['is_formatted'] ?? false,
          'isEncrypted': messageData['is_encrypted'] ?? false,
          'encryptionMetadata': messageData['encryption_metadata'],
          'keyVersion': messageData['key_version'] ?? 1,
        };

        final message = Message.fromJson(mappedMessageData);

        // Decrypt message if encrypted
        Message processedMessage = message;
        if (message.isEncrypted) {
          try {
            processedMessage = await _encryptionService.decryptMessage(message);
          } catch (e) {
            debugPrint('❌ Failed to decrypt message ${message.id}: $e');
            processedMessage = message.copyWith(
              content: '[Encrypted message - decryption failed]',
            );
          }
        }

        // Load sender profile data
        final senderProfile = await _getSenderProfile(message.senderId);
        processedMessage = processedMessage.copyWith(
          senderName: senderProfile?.displayName ?? senderProfile?.username,
          senderAvatarUrl: senderProfile?.avatarUrl,
        );

        // Load reply-to message if exists
        if (message.replyToId != null) {
          final replyToMessage = await _getMessage(message.replyToId!);
          processedMessage =
              processedMessage.copyWith(replyToMessage: replyToMessage);
        }

        messages.add(processedMessage);
      }

      _messagesCache[conversationId] = messages;
      _messagesController.add(messages);
    } catch (e) {
      debugPrint('❌ Error handling messages update: $e');
    }
  }

  /// Load messages for conversation
  Future<void> _loadMessages(String conversationId,
      {int limit = 50, int offset = 0}) async {
    try {
      debugPrint('📥 Loading messages for conversation: $conversationId');

      final response = await _supabase
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true)
          .range(offset, offset + limit - 1);

      // Cast the response to the expected type
      final List<Map<String, dynamic>> messagesData =
          (response as List<dynamic>).cast<Map<String, dynamic>>();
      await _handleMessagesUpdate(conversationId, messagesData);
    } catch (e) {
      debugPrint('❌ Error loading messages: $e');
    }
  }

  /// Get sender profile
  Future<Profile?> _getSenderProfile(String senderId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('username, display_name, avatar_url')
          .eq('id', senderId)
          .maybeSingle();

      if (response == null) return null;

      return Profile.fromJson({
        'id': senderId,
        ...response,
      });
    } catch (e) {
      debugPrint('❌ Error getting sender profile: $e');
      return null;
    }
  }

  /// Get a specific message
  Future<Message?> _getMessage(String messageId) async {
    try {
      final response = await _supabase
          .from('messages')
          .select()
          .eq('id', messageId)
          .maybeSingle();

      if (response == null) return null;

      return Message.fromJson(response);
    } catch (e) {
      debugPrint('❌ Error getting message: $e');
      return null;
    }
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead(String conversationId) async {
    if (_currentUserId == null) return;

    try {
      // Update last read timestamp for current user
      await _supabase
          .from('conversation_participants')
          .update({'last_read_at': DateTime.now().toIso8601String()})
          .eq('conversation_id', conversationId)
          .eq('user_id', _currentUserId);

      // Update message status to read for messages from other users
      await _supabase
          .from('messages')
          .update({'status': 'read'})
          .eq('conversation_id', conversationId)
          .neq('sender_id', _currentUserId)
          .eq('status', 'delivered');

      debugPrint('✅ Marked messages as read for conversation: $conversationId');
    } catch (e) {
      debugPrint('❌ Error marking messages as read: $e');
    }
  }

  /// Set typing status
  Future<void> setTypingStatus(String conversationId, bool isTyping) async {
    if (_currentUserId == null) return;

    try {
      // First try to update existing record
      final updateResult = await _supabase
          .from('typing_status')
          .update({
            'is_typing': isTyping,
            'last_updated': DateTime.now().toIso8601String(),
          })
          .eq('conversation_id', conversationId)
          .eq('user_id', _currentUserId)
          .select();

      // If no rows were updated, insert a new record
      if (updateResult == null || updateResult.isEmpty) {
        await _supabase.from('typing_status').insert({
          'conversation_id': conversationId,
          'user_id': _currentUserId,
          'is_typing': isTyping,
          'last_updated': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('❌ Error setting typing status: $e');
      // Try alternative approach if upsert fails
      try {
        await _supabase
            .from('typing_status')
            .delete()
            .eq('conversation_id', conversationId)
            .eq('user_id', _currentUserId);

        await _supabase.from('typing_status').insert({
          'conversation_id': conversationId,
          'user_id': _currentUserId,
          'is_typing': isTyping,
          'last_updated': DateTime.now().toIso8601String(),
        });
      } catch (e2) {
        debugPrint('❌ Error with alternative typing status approach: $e2');
      }
    }
  }

  /// Subscribe to typing status
  Future<void> subscribeToTypingStatus(String conversationId) async {
    try {
      _typingSubscription = _supabase
          .from('typing_status')
          .stream(primaryKey: ['id'])
          .eq('conversation_id', conversationId)
          .listen((List<Map<String, dynamic>> data) {
            // Filter for typing users and exclude current user
            final typingUsers = data
                .where((item) =>
                    item['is_typing'] == true &&
                    item['user_id'] != _currentUserId)
                .map((item) => item['user_id'] as String)
                .toList();

            _typingStatusController.add({conversationId: typingUsers});
          });
    } catch (e) {
      debugPrint('❌ Error subscribing to typing status: $e');
    }
  }

  /// Add reaction to message
  Future<bool> addReaction(String messageId, String emoji) async {
    if (_currentUserId == null) return false;

    try {
      // Get current message
      final messageResponse = await _supabase
          .from('messages')
          .select('reactions')
          .eq('id', messageId)
          .single();

      final List<dynamic> reactionsJson = messageResponse['reactions'] ?? [];
      final List<MessageReaction> reactions =
          reactionsJson.map((r) => MessageReaction.fromJson(r)).toList();

      // Check if user already reacted with this emoji
      final existingIndex = reactions.indexWhere(
        (r) => r.userId == _currentUserId && r.emoji == emoji,
      );

      if (existingIndex >= 0) {
        // Remove existing reaction
        reactions.removeAt(existingIndex);
      } else {
        // Add new reaction
        reactions.add(MessageReaction(
          userId: _currentUserId!,
          emoji: emoji,
          createdAt: DateTime.now(),
        ));
      }

      // Update message
      await _supabase.from('messages').update({
        'reactions': jsonEncode(reactions.map((r) => r.toJson()).toList()),
      }).eq('id', messageId);

      return true;
    } catch (e) {
      debugPrint('❌ Error adding reaction: $e');
      return false;
    }
  }

  /// Delete a message
  Future<bool> deleteMessage(String messageId,
      {bool forEveryone = false}) async {
    if (_currentUserId == null) return false;

    try {
      if (forEveryone) {
        // Mark as deleted for everyone
        await _supabase
            .from('messages')
            .update({
              'is_deleted': true,
              'content': '',
              'media_data': null,
              'location_data': null,
            })
            .eq('id', messageId)
            .eq('sender_id', _currentUserId);
      } else {
        // For now, just mark as deleted for everyone
        // TODO: Implement delete for me only (would require a separate table)
        await _supabase
            .from('messages')
            .update({
              'is_deleted': true,
              'content': '',
              'media_data': null,
              'location_data': null,
            })
            .eq('id', messageId)
            .eq('sender_id', _currentUserId);
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error deleting message: $e');
      return false;
    }
  }

  /// Upload a media file with encryption
  Future<MediaData?> _uploadMediaFile(File file, String conversationId) async {
    try {
      final String fileName = '${_uuid.v4()}${path.extension(file.path)}';
      final String filePath = 'conversations/$conversationId/$fileName';

      // Determine mime type
      final String mimeType = _getMimeType(file.path);

      // Encrypt file if needed
      File fileToUpload = file;
      try {
        final encryptedFile =
            await _encryptionService.encryptMediaFile(file, conversationId);
        if (encryptedFile != null) {
          fileToUpload = encryptedFile;
          debugPrint('📁 Media file encrypted successfully');
        }
      } catch (e) {
        debugPrint(
            '⚠️ Failed to encrypt media file, uploading unencrypted: $e');
      }

      // Upload to Supabase storage
      await _supabase.storage.from('pulse_media').upload(
            filePath,
            fileToUpload,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: true,
            ),
          );

      // Get the public URL
      final String fileUrl =
          _supabase.storage.from('pulse_media').getPublicUrl(filePath);

      // Get file size
      final int fileSize = await file.length();

      return MediaData(
        url: fileUrl,
        mimeType: mimeType,
        size: fileSize,
        fileName: fileName,
        isEncrypted: fileToUpload != file,
      );
    } catch (e) {
      debugPrint('❌ Error uploading media file: $e');
      return null;
    }
  }

  /// Get mime type from file extension
  String _getMimeType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();

    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.mp3':
        return 'audio/mp3';
      case '.m4a':
        return 'audio/aac';
      case '.wav':
        return 'audio/wav';
      default:
        return 'application/octet-stream';
    }
  }

  /// Unsubscribe from current conversation
  Future<void> unsubscribeFromMessages() async {
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _currentConversationId = null;
    debugPrint('🔕 Unsubscribed from messages');
  }

  /// Dispose all resources
  void dispose() {
    debugPrint('🧹 Disposing ConversationService');

    // Cancel all subscriptions
    _conversationsSubscription?.cancel();
    _messagesSubscription?.cancel();
    _typingSubscription?.cancel();
    _connectivitySubscription?.cancel();

    // Close all stream controllers
    _conversationsController.close();
    _messagesController.close();
    _newMessageController.close();
    _messageStatusController.close();
    _typingStatusController.close();

    // Clear caches
    _conversationsCache.clear();
    _messagesCache.clear();
    _participantsCache.clear();
    _lastFetchTime.clear();

    // Dispose other services
    _locationService.dispose();
  }
}
