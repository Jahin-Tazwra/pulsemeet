import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'encryption_isolate_service.dart';
import 'conversation_key_cache.dart';
import 'message_cache_service.dart';
import 'optimistic_ui_service.dart';
import 'package:mime/mime.dart';

import 'package:pulsemeet/models/conversation.dart';

import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/location_service.dart';
import 'package:pulsemeet/services/unified_encryption_service.dart';
import 'package:pulsemeet/services/key_management_service.dart';
import 'package:pulsemeet/services/network_resilience_service.dart';
import 'progressive_message_loader.dart';
import 'message_status_service.dart';
import 'performance_monitoring_service.dart';
import 'database_optimization_service.dart';

/// Unified service for handling all conversation and messaging functionality
class ConversationService {
  static final ConversationService _instance = ConversationService._internal();

  factory ConversationService() => _instance;

  ConversationService._internal() {
    _initService();
  }

  final SupabaseClient _supabase = Supabase.instance.client;
  final LocationService _locationService = LocationService();
  final UnifiedEncryptionService _encryptionService =
      UnifiedEncryptionService();
  final KeyManagementService _keyManagementService = KeyManagementService();
  final NetworkResilienceService _networkService = NetworkResilienceService();
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
  String? _currentUserId;
  List<Message> _offlineQueue = [];

  // Batch processing for offline queue
  Timer? _offlineQueueSaveTimer;
  bool _offlineQueueDirty = false;

  // Debounce timer for conversation updates to prevent feedback loops
  Timer? _conversationUpdateTimer;

  // Debug logging control
  static const bool _verboseLogging =
      false; // Set to true for detailed debugging

  // Performance tracking
  static const bool _performanceLogging = true; // Always track performance
  final Map<String, Stopwatch> _performanceTimers = {};

  // Caches for performance
  final Map<String, List<Conversation>> _conversationsCache = {};
  final Map<String, List<Message>> _messagesCache = {};
  final Map<String, List<ConversationParticipant>> _participantsCache = {};
  final Map<String, DateTime> _lastFetchTime = {};

  // Performance optimization: Cache decrypted last messages to avoid repeated decryption
  final Map<String, Message> _lastMessageCache = {};
  final Map<String, DateTime> _lastMessageCacheTime = {};
  static const Duration _lastMessageCacheExpiry = Duration(minutes: 5);

  // PERFORMANCE OPTIMIZATION: Key caching to avoid repeated database lookups
  final Map<String, String> _conversationKeyCache = {};
  final Map<String, DateTime> _keyCacheTimestamps = {};
  static const Duration _keyCacheExpiry = Duration(minutes: 30);

  // PERFORMANCE FIX: Track recent status updates to prevent duplicates
  final Set<String> _recentStatusUpdates = <String>{};

  /// Get cached encryption key or fetch from database (OPTIMIZED)
  Future<String?> _getCachedConversationKey(String conversationId) async {
    // Check if key is cached and not expired
    final cachedKey = _conversationKeyCache[conversationId];
    final cacheTime = _keyCacheTimestamps[conversationId];

    if (cachedKey != null && cacheTime != null) {
      final isExpired = DateTime.now().difference(cacheTime) > _keyCacheExpiry;
      if (!isExpired) {
        debugPrint('⚡ Using cached encryption key for $conversationId');
        return cachedKey;
      } else {
        // Remove expired key
        _conversationKeyCache.remove(conversationId);
        _keyCacheTimestamps.remove(conversationId);
      }
    }

    // Use the existing _getConversationKeyForDecryption method which handles both DM and pulse chats
    try {
      final keyString = await _getConversationKeyForDecryption(conversationId);
      _conversationKeyCache[conversationId] = keyString;
      _keyCacheTimestamps[conversationId] = DateTime.now();
      debugPrint('💾 Cached encryption key for $conversationId');
      return keyString;
    } catch (e) {
      debugPrint('❌ Error fetching encryption key for $conversationId: $e');
    }

    return null;
  }

  /// Clear key cache for a conversation (useful when key changes)
  void _clearKeyCache(String conversationId) {
    _conversationKeyCache.remove(conversationId);
    _keyCacheTimestamps.remove(conversationId);
    debugPrint('🗑️ Cleared key cache for $conversationId');
  }

  /// Update last message cache (for optimistic UI updates)
  void updateLastMessageCache(String conversationId, Message message) {
    _lastMessageCache[conversationId] = message;
    _lastMessageCacheTime[conversationId] = DateTime.now();
    debugPrint(
        '💾 Updated last message cache for conversation: $conversationId');

    // CRITICAL FIX: Trigger conversation list refresh to show new last message
    _refreshConversationListWithNewMessage(conversationId, message);

    // ENHANCEMENT: Also trigger a real-time conversation update
    _triggerRealTimeConversationUpdate(conversationId, message);

    // CRITICAL FIX: Immediately update conversation list with new preview (0ms delay)
    _updateConversationPreviewInstantly(conversationId, message);
  }

  /// Refresh conversation list when a new message is sent
  void _refreshConversationListWithNewMessage(
      String conversationId, Message newMessage) {
    try {
      // Get current conversations from cache
      final currentConversations = _conversationsCache[_currentUserId];
      if (currentConversations != null) {
        // Create a preview of the new message content
        String messagePreview = newMessage.content;
        if (messagePreview.length > 50) {
          messagePreview = '${messagePreview.substring(0, 50)}...';
        }

        // Find and update the conversation with the new last message
        final updatedConversations = currentConversations.map((conversation) {
          if (conversation.id == conversationId) {
            // Create updated conversation with new last message preview
            return conversation.copyWith(
              lastMessagePreview: messagePreview,
              lastMessageAt: newMessage.createdAt,
              updatedAt: newMessage.createdAt,
            );
          }
          return conversation;
        }).toList();

        // Sort conversations by last message time (newest first)
        updatedConversations.sort((a, b) {
          final aTime = a.lastMessageAt ?? a.updatedAt;
          final bTime = b.lastMessageAt ?? b.updatedAt;
          return bTime.compareTo(aTime);
        });

        // Update cache and emit to UI
        _conversationsCache[_currentUserId!] = updatedConversations;
        _conversationsController.add(updatedConversations);

        debugPrint(
            '🔄 Refreshed conversation list with new message for: $conversationId');
        debugPrint('🔄 Updated preview: $messagePreview');
      }
    } catch (e) {
      debugPrint('❌ Error refreshing conversation list: $e');
    }
  }

  /// Trigger real-time conversation update for immediate UI refresh
  void _triggerRealTimeConversationUpdate(
      String conversationId, Message message) {
    try {
      debugPrint(
          '🔄 Triggering real-time conversation update for: $conversationId');

      // Get current conversations from cache
      final currentConversations = _conversationsCache[_currentUserId!] ?? [];
      if (currentConversations.isEmpty) {
        debugPrint('📭 No cached conversations to update');
        return;
      }

      // Find and update the specific conversation
      bool conversationUpdated = false;
      final updatedConversations = currentConversations.map((conversation) {
        if (conversation.id == conversationId) {
          conversationUpdated = true;
          final messagePreview = message.getDisplayContent();
          debugPrint('📝 Updating conversation preview: $messagePreview');

          return conversation.copyWith(
            lastMessagePreview: messagePreview,
            lastMessageAt: message.createdAt,
            updatedAt: message.createdAt,
          );
        }
        return conversation;
      }).toList();

      if (conversationUpdated) {
        // Sort conversations by last message time (newest first)
        updatedConversations.sort((a, b) {
          final aTime = a.lastMessageAt ?? a.updatedAt;
          final bTime = b.lastMessageAt ?? b.updatedAt;
          return bTime.compareTo(aTime);
        });

        // Update cache and emit to stream
        _conversationsCache[_currentUserId!] = updatedConversations;
        _conversationsController.add(updatedConversations);

        debugPrint('✅ Real-time conversation update completed');
      } else {
        debugPrint('⚠️ Conversation $conversationId not found in cache');
      }
    } catch (e) {
      debugPrint('❌ Error in real-time conversation update: $e');
    }
  }

  /// Update conversation preview instantly for immediate UI feedback (0ms delay)
  void _updateConversationPreviewInstantly(
      String conversationId, Message message) {
    try {
      debugPrint(
          '⚡ Updating conversation preview instantly for: $conversationId');

      // Get current conversations from cache
      final currentConversations = _conversationsCache[_currentUserId!] ?? [];
      if (currentConversations.isEmpty) {
        debugPrint('📭 No cached conversations to update instantly');
        return;
      }

      // Find and update the specific conversation
      bool conversationUpdated = false;
      final updatedConversations = currentConversations.map((conversation) {
        if (conversation.id == conversationId) {
          conversationUpdated = true;
          final messagePreview = message.getDisplayContent();
          debugPrint('📝 Instant preview update: $messagePreview');

          return conversation.copyWith(
            lastMessagePreview: messagePreview,
            lastMessageAt: message.createdAt,
            updatedAt: message.createdAt,
          );
        }
        return conversation;
      }).toList();

      if (conversationUpdated) {
        // Sort conversations by last message time (newest first)
        updatedConversations.sort((a, b) {
          final aTime = a.lastMessageAt ?? a.updatedAt;
          final bTime = b.lastMessageAt ?? b.updatedAt;
          return bTime.compareTo(aTime);
        });

        // Update cache and emit to stream immediately
        _conversationsCache[_currentUserId!] = updatedConversations;
        _conversationsController.add(updatedConversations);

        debugPrint(
            '✅ Instant conversation preview update completed (0ms delay)');
      } else {
        debugPrint(
            '⚠️ Conversation $conversationId not found in cache for instant update');
      }
    } catch (e) {
      debugPrint('❌ Error in instant conversation preview update: $e');
    }
  }

  // High-performance services for instant UI responsiveness
  late final EncryptionIsolateService _encryptionIsolate;
  late final ConversationKeyCache _keyCache;
  late final MessageCacheService _messageCache;
  late final OptimisticUIService _optimisticUI;
  late final ProgressiveMessageLoader _progressiveLoader;
  late final MessageStatusService _messageStatusService;
  late final PerformanceMonitoringService _performanceMonitor;
  late final DatabaseOptimizationService _databaseOptimizer;

  // Getters
  Stream<List<Conversation>> get conversationsStream =>
      _conversationsController.stream;
  Stream<List<Message>> get messagesStream => _messagesController.stream;
  Stream<Message> get newMessageStream => _newMessageController.stream;
  Stream<String> get messageStatusStream => _messageStatusController.stream;
  Stream<Map<String, List<String>>> get typingStatusStream =>
      _typingStatusController.stream;

  /// Start performance timer
  void _startPerformanceTimer(String operation) {
    if (_performanceLogging) {
      _performanceTimers[operation] = Stopwatch()..start();
    }
  }

  /// Stop performance timer and log result
  void _stopPerformanceTimer(String operation) {
    if (_performanceLogging && _performanceTimers.containsKey(operation)) {
      final timer = _performanceTimers[operation]!;
      timer.stop();
      final durationMs = timer.elapsedMilliseconds;

      // Record in performance monitor for comprehensive tracking
      _performanceMonitor.recordMetric(operation, durationMs);

      debugPrint('⏱️ PERFORMANCE: $operation took ${durationMs}ms');
      _performanceTimers.remove(operation);
    }
  }

  /// Ensure OptimisticUI status subscription is initialized (can be called multiple times)
  void ensureOptimisticUIStatusSubscription() {
    debugPrint(
        '🔧 ConversationService: Ensuring OptimisticUI status subscription...');
    if (_optimisticUI != null) {
      _optimisticUI.ensureStatusSubscriptionInitialized();
      debugPrint(
          '✅ ConversationService: OptimisticUI status subscription ensured');
    } else {
      debugPrint('⚠️ ConversationService: OptimisticUI not initialized yet');
    }
  }

  /// Initialize the service
  Future<void> _initService() async {
    if (_isInitialized) return;

    _startPerformanceTimer('ConversationService_Init');
    debugPrint('🚀 Initializing ConversationService');

    // Initialize network resilience service first
    await _networkService.initialize();

    // Initialize high-performance services for instant UI responsiveness
    debugPrint(
        '🔧 ConversationService: About to initialize high-performance services...');
    _encryptionIsolate = EncryptionIsolateService.instance;
    _keyCache = ConversationKeyCache.instance;
    _messageCache = MessageCacheService();
    debugPrint(
        '🔧 ConversationService: About to initialize OptimisticUIService...');
    _optimisticUI = OptimisticUIService.instance;
    // Ensure status subscription is initialized
    debugPrint(
        '🔧 ConversationService: About to ensure status subscription...');
    _optimisticUI.ensureStatusSubscriptionInitialized();
    debugPrint(
        '✅ ConversationService: OptimisticUIService initialized with status subscription');
    _progressiveLoader = ProgressiveMessageLoader();
    _messageStatusService = MessageStatusService.instance;
    _performanceMonitor = PerformanceMonitoringService();
    _databaseOptimizer = DatabaseOptimizationService();

    // Initialize message cache for instant performance
    _messageCache.initialize();

    // Initialize database optimizations
    await _databaseOptimizer.initialize();

    // Initialize encryption isolate in background (non-blocking)
    _encryptionIsolate.initialize().catchError((e) {
      debugPrint('⚠️ Encryption isolate initialization failed: $e');
    });

    // Initialize encryption services
    await _initializeEncryption();

    // Ensure typing status table exists
    await _ensureTypingStatusTable();

    // Load offline queue
    await _loadOfflineQueue();

    // Use network service for connectivity monitoring
    _isOnline = _networkService.isOnline;

    // Process offline queue if we're online
    if (_isOnline && _offlineQueue.isNotEmpty) {
      debugPrint('🔄 Processing offline queue on startup');
      _processOfflineQueue();
    }

    // Get current user
    _currentUserId = _supabase.auth.currentUser?.id;
    debugPrint('👤 Current user ID: $_currentUserId');
    debugPrint('🌐 Online status: $_isOnline');
    debugPrint('🔗 Supabase URL: ${_supabase.supabaseUrl}');

    // Test Supabase connectivity
    final connectivityOk = await _networkService.testSupabaseConnectivity();
    if (!connectivityOk) {
      debugPrint('⚠️ Supabase connectivity test failed during initialization');
    }

    _isInitialized = true;
    _stopPerformanceTimer('ConversationService_Init');
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

  /// Ensure typing_status table exists with correct schema
  Future<void> _ensureTypingStatusTable() async {
    try {
      // Test if the table exists and has the correct schema
      await _supabase
          .from('typing_status')
          .select('conversation_id, user_id, is_typing, last_updated')
          .limit(1);
      debugPrint('✅ typing_status table exists with correct schema');
    } catch (e) {
      debugPrint('⚠️ typing_status table issue detected: $e');
      debugPrint('🔧 Attempting to create/fix typing_status table...');

      try {
        // Create the table with correct schema
        await _supabase.rpc('exec_sql', params: {
          'sql': '''
            CREATE TABLE IF NOT EXISTS typing_status (
              id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
              conversation_id UUID NOT NULL,
              user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
              is_typing BOOLEAN NOT NULL DEFAULT false,
              last_updated TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
              CONSTRAINT typing_status_conversation_id_user_id_key UNIQUE(conversation_id, user_id)
            );

            CREATE INDEX IF NOT EXISTS idx_typing_status_conversation_id ON typing_status(conversation_id);
            CREATE INDEX IF NOT EXISTS idx_typing_status_user_id ON typing_status(user_id);
            CREATE INDEX IF NOT EXISTS idx_typing_status_is_typing ON typing_status(is_typing);

            ALTER TABLE typing_status ENABLE ROW LEVEL SECURITY;
          '''
        });
        debugPrint('✅ typing_status table created/fixed successfully');
      } catch (e2) {
        debugPrint('❌ Failed to create/fix typing_status table: $e2');
        // Continue without typing status functionality
      }
    }
  }

  /// Load offline queue from local storage
  Future<void> _loadOfflineQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Handle both String and List<String> cases for backward compatibility
      dynamic queueData;

      // Try to get as String first (new format)
      final queueJson = prefs.getString('offline_message_queue');
      if (queueJson != null) {
        try {
          queueData = jsonDecode(queueJson);
        } catch (e) {
          debugPrint(
              '⚠️ Failed to decode queue JSON, trying List<String> format: $e');
          queueData = null;
        }
      }

      // Fallback to List<String> format (legacy)
      if (queueData == null) {
        final queueStringList = prefs.getStringList('offline_message_queue');
        if (queueStringList != null) {
          try {
            queueData =
                queueStringList.map((item) => jsonDecode(item)).toList();
            debugPrint(
                '📱 Loaded offline queue from legacy List<String> format');
          } catch (e) {
            debugPrint('⚠️ Failed to decode legacy queue format: $e');
            queueData = [];
          }
        }
      }

      if (queueData != null && queueData is List) {
        _offlineQueue = queueData
            .whereType<Map<String, dynamic>>()
            .map((data) {
              try {
                return Message.fromJson(data);
              } catch (e) {
                debugPrint('⚠️ Failed to parse offline message: $e');
                return null;
              }
            })
            .where((message) => message != null)
            .cast<Message>()
            .toList();
        debugPrint('📱 Loaded ${_offlineQueue.length} offline messages');
      }
    } catch (e) {
      debugPrint('❌ Error loading offline queue: $e');
      // Clear corrupted data
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('offline_message_queue');
        debugPrint('🧹 Cleared corrupted offline queue data');
      } catch (clearError) {
        debugPrint('❌ Failed to clear corrupted queue data: $clearError');
      }
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

  /// Add message to offline queue with batched persistence
  void _addToOfflineQueue(Message message) {
    _offlineQueue.add(message);
    _offlineQueueDirty = true;
    debugPrint('📱 Added message to offline queue: ${message.id}');

    // Schedule batched save
    _scheduleBatchedOfflineQueueSave();
  }

  /// Schedule batched save of offline queue to reduce I/O
  void _scheduleBatchedOfflineQueueSave() {
    _offlineQueueSaveTimer?.cancel();
    _offlineQueueSaveTimer = Timer(const Duration(seconds: 2), () {
      if (_offlineQueueDirty) {
        _saveOfflineQueue();
        _offlineQueueDirty = false;
      }
    });
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
          .listen((List<Map<String, dynamic>> data) {
            debugPrint(
                '📡 Received real-time conversation update: ${data.length} items');

            // CRITICAL FIX: Debounce conversation updates to prevent feedback loops
            // Cancel any pending update and schedule a new one
            _conversationUpdateTimer?.cancel();
            _conversationUpdateTimer =
                Timer(const Duration(milliseconds: 300), () {
              // Process updates asynchronously to avoid blocking the stream
              _handleConversationsStreamUpdate(data).catchError((error) {
                debugPrint('❌ Error processing conversation update: $error');
                _conversationsController.addError(error);
              });
            });
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
      debugPrint('🔄 Real-time update triggered for recipient');

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

          // Keep snake_case database fields as the generated parser expects them
          final mappedConversation = {
            'id': conversationId, // Already validated as non-null
            'type': rawData['type']?.toString() ?? 'direct_message',
            'title': rawData['title']?.toString(),
            'description': rawData['description']?.toString(),
            'avatar_url': rawData['avatar_url']?.toString(),
            'pulse_id': rawData['pulse_id']?.toString(),
            'created_by': rawData['created_by']?.toString(),
            'created_at': rawData['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
            'updated_at': rawData['updated_at']?.toString() ??
                DateTime.now().toIso8601String(),
            'last_message_at': rawData['last_message_at']?.toString(),
            'is_archived': rawData['is_archived'] ?? false,
            'is_muted': rawData['is_muted'] ?? false,
            'settings': rawData['settings'] ?? {},
            'encryption_enabled': rawData['encryption_enabled'] ?? true,
            'encryption_key_id': rawData['encryption_key_id']?.toString(),
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
          if (_verboseLogging) {
            debugPrint(
                '📝 Creating conversation from: ${conversationData['id']}');
          }

          // Validate required fields before creating conversation
          if (conversationData['id'] == null) {
            debugPrint('⚠️ Skipping conversation with null ID');
            continue;
          }

          if (conversationData['createdAt'] == null) {
            if (_verboseLogging) {
              debugPrint(
                  '⚠️ Adding default createdAt for conversation ${conversationData['id']}');
            }
            conversationData['createdAt'] = DateTime.now().toIso8601String();
          }

          if (conversationData['updatedAt'] == null) {
            if (_verboseLogging) {
              debugPrint(
                  '⚠️ Adding default updatedAt for conversation ${conversationData['id']}');
            }
            conversationData['updatedAt'] = DateTime.now().toIso8601String();
          }

          final conversation = Conversation.fromJson(conversationData);

          // Load participants, unread count, and last message in parallel for better performance
          final results = await Future.wait([
            _getConversationParticipants(conversation.id),
            _getUnreadMessageCount(conversation.id)
                .timeout(const Duration(seconds: 1), onTimeout: () => 0),
            _getLastMessage(conversation.id)
                .timeout(const Duration(seconds: 1), onTimeout: () => null),
          ]);

          final participants = results[0] as List<ConversationParticipant>;
          final unreadCount = results[1] as int;
          final lastMessage = results[2] as Message?;

          if (_verboseLogging) {
            debugPrint(
                '👥 Found ${participants.length} participants for conversation ${conversation.id}');
          }

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

          // ENHANCEMENT: Get last message preview with proper encryption handling
          String? lastMessagePreview;
          final settingsPreview =
              conversation.settings['last_message_preview'] as String?;
          final isLastMessageEncrypted =
              conversation.settings['last_message_encrypted'] as bool? ?? false;
          final lastMessageId =
              conversation.settings['last_message_id'] as String?;

          if (settingsPreview != null && settingsPreview.isNotEmpty) {
            if (isLastMessageEncrypted &&
                lastMessage != null &&
                lastMessageId == lastMessage.id) {
              // For encrypted messages, try to use decrypted content if available
              try {
                final decryptedPreview = lastMessage.getDisplayContent();
                if (decryptedPreview.isNotEmpty &&
                    !decryptedPreview.contains('[Encrypted')) {
                  lastMessagePreview = decryptedPreview;
                  debugPrint(
                      '🔓 Using decrypted preview for encrypted message: ${conversation.id}');
                } else {
                  lastMessagePreview =
                      settingsPreview; // Fallback to generic preview
                  debugPrint(
                      '⚡ Using generic preview for encrypted message: ${conversation.id}');
                }
              } catch (e) {
                lastMessagePreview =
                    settingsPreview; // Fallback to generic preview
                debugPrint(
                    '⚠️ Failed to decrypt preview, using generic: ${conversation.id}');
              }
            } else {
              lastMessagePreview = settingsPreview;
              debugPrint(
                  '⚡ Using database preview for conversation: ${conversation.id}');
            }
          } else if (lastMessage != null) {
            lastMessagePreview = lastMessage.getDisplayContent();
            debugPrint(
                '🔓 Using decrypted preview for conversation: ${conversation.id}');
          }

          conversations.add(conversation.copyWith(
            participants: participants,
            unreadCount: unreadCount,
            lastMessagePreview: lastMessagePreview,
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

  /// Load conversations for current user with performance optimization
  Future<void> _loadConversations() async {
    final stopwatch = Stopwatch()..start();
    debugPrint('🚀 Starting conversation loading...');

    // Ensure user is authenticated before loading
    await _ensureAuthenticated();

    if (_currentUserId == null) {
      debugPrint('❌ Cannot load conversations: No current user after retry');
      _conversationsController.add([]);
      return;
    }

    try {
      debugPrint('📥 Loading conversations for user: $_currentUserId');

      // Check cache first for performance
      if (_conversationsCache.containsKey(_currentUserId!)) {
        final cachedConversations = _conversationsCache[_currentUserId!]!;
        if (cachedConversations.isNotEmpty) {
          stopwatch.stop();
          debugPrint(
              '⚡ Using cached conversations (${cachedConversations.length} items) - ${stopwatch.elapsedMilliseconds}ms');
          _conversationsController.add(cachedConversations);
          // Still load fresh data in background
          _loadConversationsFromDatabase();
          return;
        }
      }

      await _loadConversationsFromDatabase();
      stopwatch.stop();
      debugPrint(
          '✅ Total conversation loading time: ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      stopwatch.stop();
      debugPrint(
          '❌ Error loading conversations after ${stopwatch.elapsedMilliseconds}ms: $e');
      _conversationsController.addError(e);
    }
  }

  /// Load conversations from database with network resilience
  Future<void> _loadConversationsFromDatabase() async {
    final dbStopwatch = Stopwatch()..start();
    try {
      debugPrint('🔄 Starting database query...');
      final response = await _networkService.executeWithRetry(() async {
        // Use the new function that avoids RLS recursion with timeout
        return await _supabase
            .rpc('get_user_conversations')
            .timeout(const Duration(seconds: 10));
      }, operationName: 'Load conversations');

      dbStopwatch.stop();
      debugPrint(
          '📊 Database query completed in ${dbStopwatch.elapsedMilliseconds}ms');
      debugPrint('📊 RPC response type: ${response.runtimeType}');
      debugPrint(
          '📊 Loaded ${response is List ? response.length : 0} conversations from database');

      final List<dynamic> responseList = response is List ? response : [];

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

          // Keep snake_case database fields as the generated parser expects them
          return {
            'id': data['id']?.toString(),
            'type': data['type']?.toString() ?? 'direct_message',
            'title': data['title']?.toString(),
            'description': data['description']?.toString(),
            'avatar_url': data['avatar_url']?.toString(),
            'pulse_id': data['pulse_id']?.toString(),
            'created_by': data['created_by']?.toString(),
            'created_at': data['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
            'updated_at': data['updated_at']?.toString() ??
                DateTime.now().toIso8601String(),
            'last_message_at': data['last_message_at']?.toString(),
            'is_archived': data['is_archived'] ?? false,
            'is_muted': data['is_muted'] ?? false,
            'settings': data['settings'] ?? {},
            'encryption_enabled': data['encryption_enabled'] ?? true,
            'encryption_key_id': data['encryption_key_id']?.toString(),
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

      final processingStopwatch = Stopwatch()..start();
      debugPrint(
          '📝 Mapped ${conversationsData.length} conversations, processing...');
      await _handleConversationsUpdate(conversationsData);
      processingStopwatch.stop();
      debugPrint(
          '✅ Conversations processed in ${processingStopwatch.elapsedMilliseconds}ms');
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

  /// Get last message for conversation with caching
  Future<Message?> _getLastMessage(String conversationId) async {
    try {
      // Check cache first for performance
      final cachedMessage = _lastMessageCache[conversationId];
      final cacheTime = _lastMessageCacheTime[conversationId];

      if (cachedMessage != null && cacheTime != null) {
        final isExpired =
            DateTime.now().difference(cacheTime) > _lastMessageCacheExpiry;
        if (!isExpired) {
          debugPrint(
              '⚡ Using cached last message for conversation: $conversationId');
          return cachedMessage;
        } else {
          debugPrint(
              '🕐 Last message cache expired for conversation: $conversationId');
          _lastMessageCache.remove(conversationId);
          _lastMessageCacheTime.remove(conversationId);
        }
      }

      debugPrint('🔍 Getting last message for conversation: $conversationId');
      final response = await _supabase
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      if (response == null) {
        debugPrint(
            '📭 No last message found for conversation: $conversationId');
        return null;
      }

      debugPrint('📨 Raw last message response: $response');

      // Validate response data before creating Message
      if (response is! Map<String, dynamic>) {
        debugPrint(
            '⚠️ Invalid response type for last message: ${response.runtimeType}');
        return null;
      }

      // Check for required fields
      if (response['id'] == null ||
          response['conversation_id'] == null ||
          response['sender_id'] == null) {
        debugPrint('⚠️ Missing required fields in last message response');
        debugPrint('📝 Response fields: ${response.keys.toList()}');
        return null;
      }

      // Ensure all fields are properly handled with comprehensive null safety
      final safeResponse = <String, dynamic>{};

      // Required fields
      safeResponse['id'] = response['id']?.toString() ?? '';
      safeResponse['conversationId'] =
          response['conversation_id']?.toString() ?? conversationId;
      safeResponse['senderId'] = response['sender_id']?.toString() ?? '';

      // Content and type fields
      safeResponse['content'] = response['content']?.toString() ?? '';
      safeResponse['messageType'] =
          response['message_type']?.toString() ?? 'text';
      safeResponse['status'] = response['status']?.toString() ?? 'sent';

      // Date fields
      safeResponse['createdAt'] = response['created_at']?.toString() ??
          DateTime.now().toIso8601String();
      safeResponse['updatedAt'] = response['updated_at']?.toString() ??
          response['created_at']?.toString() ??
          DateTime.now().toIso8601String();

      // Optional fields with safe defaults
      safeResponse['isDeleted'] = response['is_deleted'] ?? false;
      safeResponse['isEdited'] = response['is_edited'] ?? false;
      safeResponse['editedAt'] = response['edited_at']?.toString();
      safeResponse['expiresAt'] = response['expires_at']?.toString();
      safeResponse['replyToId'] = response['reply_to_id']?.toString();
      safeResponse['forwardFromId'] = response['forward_from_id']?.toString();
      safeResponse['isFormatted'] = response['is_formatted'] ?? false;
      safeResponse['isEncrypted'] = response['is_encrypted'] ?? false;
      safeResponse['keyVersion'] = response['key_version'] ?? 1;

      // JSON fields
      safeResponse['reactions'] = response['reactions'] ?? [];
      safeResponse['mentions'] = response['mentions'] ?? [];
      safeResponse['mediaData'] = response['media_data'];
      safeResponse['locationData'] = response['location_data'];
      safeResponse['callData'] = response['call_data'];
      safeResponse['encryptionMetadata'] = response['encryption_metadata'];

      debugPrint('✅ Safe response prepared for Message.fromJson');
      final message = Message.fromJson(safeResponse);

      // Decrypt the message if it's encrypted before using for preview
      Message finalMessage = message;
      if (message.isEncrypted) {
        try {
          debugPrint(
              '🔓 Decrypting last message for conversation preview: ${message.id}');

          // Use cached key retrieval to avoid repeated database calls
          debugPrint(
              '🔑 Fetching conversation key from database: $conversationId');
          final conversationKey = await _keyCache.getConversationKey(
            conversationId,
            () => _getConversationKeyForDecryption(conversationId),
          );

          // Decrypt in background isolate to prevent UI blocking
          final decryptedContent = await _encryptionIsolate.decryptMessage(
            encryptedContent: message.content,
            conversationKey: conversationKey,
            encryptionMetadata: message.encryptionMetadata ?? {},
          );

          finalMessage = message.copyWith(
            content: decryptedContent,
            isEncrypted: false,
          );

          debugPrint(
              '✅ Last message decrypted for preview: ${decryptedContent.substring(0, math.min(50, decryptedContent.length))}...');
        } catch (e) {
          debugPrint('❌ Failed to decrypt last message for preview: $e');
          // Use original message with encrypted content rather than failing
          finalMessage = message;
        }
      }

      // Cache the final message (decrypted if possible) for performance
      _lastMessageCache[conversationId] = finalMessage;
      _lastMessageCacheTime[conversationId] = DateTime.now();
      debugPrint('💾 Cached last message for conversation: $conversationId');

      return finalMessage;
    } catch (e, stackTrace) {
      debugPrint('❌ Error getting last message for $conversationId: $e');
      debugPrint('📍 Stack trace: $stackTrace');
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

    _startPerformanceTimer('SendTextMessage_Total');
    _startPerformanceTimer('SendTextMessage_UIUpdate');
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

    // Add optimistic message to UI INSTANTLY (0ms perceived delay)
    _optimisticUI.addOptimisticMessage(
      conversationId,
      message,
      onLastMessageUpdate: updateLastMessageCache,
    );
    _newMessageController.add(message);

    // Cache the message immediately for instant access
    _messageCache.cacheProcessedMessage(messageId, message);

    // Update message status optimistically for instant UI feedback (non-blocking)
    _messageStatusService.updateMessageStatus(messageId, MessageStatus.sending);

    _stopPerformanceTimer('SendTextMessage_UIUpdate');
    debugPrint(
        '⚡ Message added to UI instantly: $messageId (0ms perceived delay)');

    // If offline, add to queue and return
    if (!_isOnline) {
      final offlineMessage = message.copyWith(isOffline: true);
      _addToOfflineQueue(offlineMessage);
      _stopPerformanceTimer('SendTextMessage_Total');
      return offlineMessage;
    }

    // Send message to server in background (non-blocking)
    _startPerformanceTimer('SendTextMessage_ServerSend');
    _sendMessageToServer(message, conversationId, replyToId)
        .then((sentMessage) {
      _stopPerformanceTimer('SendTextMessage_ServerSend');
      _stopPerformanceTimer('SendTextMessage_Total');
      if (sentMessage != null) {
        // SENDER SIDE FIX: Ensure the confirmed message uses plaintext content
        final confirmedMessage = sentMessage.isEncrypted
            ? message.copyWith(
                id: sentMessage.id,
                status: MessageStatus.sent,
                createdAt: sentMessage.createdAt,
                updatedAt: sentMessage.updatedAt,
                isEncrypted: false, // Use plaintext for sender UI
              )
            : sentMessage;

        // Confirm optimistic message with server response
        _optimisticUI.confirmMessage(
            conversationId, messageId, confirmedMessage);
        _messageStatusController.add(messageId);

        // Update message status to sent (non-blocking)
        _messageStatusService.updateMessageStatus(
            messageId, MessageStatus.sent);

        // Update cache with confirmed message
        _messageCache.cacheProcessedMessage(messageId, sentMessage);

        debugPrint('✅ Message sent successfully: $messageId');
      } else {
        // Update status to failed (non-blocking)
        _messageStatusService.updateMessageStatus(
            messageId, MessageStatus.failed);
      }
    }).catchError((e) {
      _stopPerformanceTimer('SendTextMessage_ServerSend');
      _stopPerformanceTimer('SendTextMessage_Total');
      debugPrint('❌ Error sending message in background: $e');
      // Mark optimistic message as failed
      _optimisticUI.markMessageFailed(conversationId, messageId, e.toString());
      final failedMessage = message.copyWith(
        status: MessageStatus.failed,
        isOffline: true,
      );
      _addToOfflineQueue(failedMessage);
    });

    return message; // Return immediately with optimistic message
  }

  /// Send message to server in background (non-blocking) - OPTIMIZED
  Future<Message?> _sendMessageToServer(
    Message message,
    String conversationId,
    String? replyToId,
  ) async {
    try {
      // PERFORMANCE OPTIMIZATION: Start encryption and network operations in parallel
      final encryptionStopwatch = Stopwatch()..start();

      // PERFORMANCE OPTIMIZATION: Pre-fetch encryption key to avoid delays
      final keyFuture = _getCachedConversationKey(conversationId);

      // Encrypt the message before sending
      Message messageToSend = message;
      try {
        // Wait for key to be available (should be fast due to caching)
        final cachedKey = await keyFuture;
        if (cachedKey != null) {
          debugPrint(
              '⚡ Using pre-fetched encryption key for faster encryption');
        }

        final encryptedMessage =
            await _encryptionService.encryptMessage(message);
        encryptionStopwatch.stop();

        if (encryptedMessage.isEncrypted) {
          messageToSend = encryptedMessage;
          debugPrint(
              '🔐 Message encrypted successfully (${encryptionStopwatch.elapsedMilliseconds}ms)');
        } else {
          messageToSend = encryptedMessage;
          debugPrint(
              '⚠️ Message encryption failed, sending unencrypted (${encryptionStopwatch.elapsedMilliseconds}ms)');
        }
      } catch (e) {
        encryptionStopwatch.stop();
        debugPrint(
            '⚠️ Failed to encrypt message, sending unencrypted (${encryptionStopwatch.elapsedMilliseconds}ms): $e');
      }

      // PERFORMANCE OPTIMIZATION: Send message to server with optimized payload
      final networkStopwatch = Stopwatch()..start();

      // Prepare optimized payload (minimize data transfer)
      final payload = {
        'id': message.id,
        'conversation_id': conversationId,
        'sender_id': _currentUserId,
        'message_type': messageToSend.messageType.name,
        'content': messageToSend.content,
        'created_at': message.createdAt.toIso8601String(),
        'status': 'sent',
        'is_encrypted': messageToSend.isEncrypted,
      };

      // Only add optional fields if they have values (reduce payload size)
      if (messageToSend.isFormatted) payload['is_formatted'] = true;
      if (replyToId != null) payload['reply_to_id'] = replyToId;
      if (messageToSend.encryptionMetadata?.isNotEmpty == true) {
        payload['encryption_metadata'] = messageToSend.encryptionMetadata;
      }
      if (messageToSend.keyVersion != null && messageToSend.keyVersion > 0) {
        payload['key_version'] = messageToSend.keyVersion;
      }

      final response = await _networkService.executeWithRetry(() async {
        return await _supabase
            .from('messages')
            .insert(payload)
            .select()
            .single();
      }, operationName: 'Send text message');

      networkStopwatch.stop();
      debugPrint(
          '📡 Server request completed (${networkStopwatch.elapsedMilliseconds}ms)');

      // Map database response to expected format with null safety
      final now = DateTime.now().toIso8601String();
      final mappedResponse = {
        'id': response['id'] ?? '',
        'conversationId': response['conversation_id'] ?? '',
        'senderId': response['sender_id'] ?? '',
        'messageType': response['message_type'] ?? 'text',
        'content': response['content'] ?? '',
        'isDeleted': response['is_deleted'] ?? false,
        'isEdited': response['is_edited'] ?? false,
        'createdAt': response['created_at'] ?? now,
        'updatedAt': response['updated_at'] ?? now,
        'editedAt': response['edited_at'],
        'expiresAt': response['expires_at'],
        'status': response['status'] ?? 'sent',
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

      // SENDER SIDE FIX: Don't decrypt the message on sender side - use original plaintext
      Message finalMessage = sentMessage;
      if (sentMessage.isEncrypted) {
        debugPrint(
            '🔓 Sender side: Using original plaintext content for UI display');
        // For sender side, use the original plaintext message content
        // The encrypted version is stored on server, but UI shows original content
        finalMessage = message.copyWith(
          id: sentMessage.id,
          status: MessageStatus.sent,
          createdAt: sentMessage.createdAt,
          updatedAt: sentMessage.updatedAt,
          isEncrypted: false, // Mark as not encrypted for UI display
        );
      }

      _messageStatusController.add(message.id);

      debugPrint('✅ Message sent to server successfully');
      return finalMessage;
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

      // Map database response to expected format with null safety
      final nowString = DateTime.now().toIso8601String();
      final mappedResponse = {
        'id': response['id'] ?? '',
        'conversationId': response['conversation_id'] ?? '',
        'senderId': response['sender_id'] ?? '',
        'messageType': response['message_type'] ?? 'text',
        'content': response['content'] ?? '',
        'isDeleted': response['is_deleted'] ?? false,
        'isEdited': response['is_edited'] ?? false,
        'createdAt': response['created_at'] ?? nowString,
        'updatedAt': response['updated_at'] ?? nowString,
        'editedAt': response['edited_at'],
        'expiresAt': response['expires_at'],
        'status': response['status'] ?? 'sent',
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

      // Decrypt the message if it's encrypted before returning
      Message finalMessage = sentMessage;
      if (sentMessage.isEncrypted) {
        try {
          finalMessage = await _encryptionService.decryptMessage(sentMessage);
          debugPrint('🔓 Server image message decrypted for UI display');
        } catch (e) {
          debugPrint(
              '⚠️ Failed to decrypt server image message, using original: $e');
          // Use the original message data for UI display
          finalMessage = messageWithMedia.copyWith(
            id: sentMessage.id,
            status: MessageStatus.sent,
            createdAt: sentMessage.createdAt,
            updatedAt: sentMessage.updatedAt,
          );
        }
      }

      _messageStatusController.add(messageId);

      return finalMessage;
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
      // Track current conversation for debugging
      debugPrint('📍 Now tracking conversation: $conversationId');

      // Subscribe to messages real-time updates with smart change detection
      _messagesSubscription = _supabase
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true)
          .listen((List<Map<String, dynamic>> data) {
            // CRITICAL FIX: Only process if there are actual changes
            _handleMessagesUpdateSmart(conversationId, data)
                .catchError((error) {
              debugPrint('❌ Error processing message update: $error');
            });
          }, onError: (error) {
            debugPrint('❌ Error in messages stream: $error');
          });

      // REAL-TIME READ STATUS FIX: Subscribe to message status updates specifically
      _subscribeToMessageStatusUpdates(conversationId);

      // Skip loading initial messages here since progressive loading handles it
      // await _loadMessages(conversationId); // Removed to prevent overriding progressive loading
    } catch (e) {
      debugPrint('❌ Error subscribing to messages: $e');
    }
  }

  /// Handle messages update from real-time subscription with smart change detection
  Future<void> _handleMessagesUpdateSmart(
      String conversationId, List<Map<String, dynamic>> data) async {
    try {
      // CRITICAL FIX: Check if this is a redundant update
      final cachedMessages = _messagesCache[conversationId] ?? [];

      // CROSS-USER REAL-TIME FIX: Prioritize detecting new messages from other users
      final cachedIds = cachedMessages.map((m) => m.id).toSet();
      final newIds = data.map((d) => d['id'] as String).toSet();

      // Check for completely new messages (highest priority for real-time delivery)
      final newMessageIds = newIds.difference(cachedIds);
      if (newMessageIds.isNotEmpty) {
        debugPrint(
            '🚀 REAL-TIME: Detected ${newMessageIds.length} NEW messages from other users: ${newMessageIds.take(3).join(', ')}${newMessageIds.length > 3 ? '...' : ''}');

        // Fast-track new messages for instant delivery
        await _handleMessagesUpdate(conversationId, data);
        return;
      }

      // Quick check: if message count and IDs are identical, check for changes
      if (cachedMessages.length == data.length && cachedMessages.isNotEmpty) {
        if (cachedIds.length == newIds.length &&
            cachedIds.containsAll(newIds)) {
          // Check if any message content/status has actually changed
          bool hasChanges = false;
          final cachedMap = <String, Message>{};
          for (final msg in cachedMessages) {
            cachedMap[msg.id] = msg;
          }

          for (final rawMessage in data) {
            final id = rawMessage['id'] as String;
            final cachedMessage = cachedMap[id];
            if (cachedMessage == null) {
              hasChanges = true;
              break;
            }

            // Check for content, status, or timestamp changes
            final newContent = rawMessage['content'] as String? ?? '';
            final newStatus = MessageStatus.values.firstWhere(
              (s) =>
                  s.toString().split('.').last ==
                  (rawMessage['status'] as String? ?? 'sent'),
              orElse: () => MessageStatus.sent,
            );
            final newUpdatedAt =
                DateTime.parse(rawMessage['updated_at'] as String);

            if (cachedMessage.content != newContent ||
                cachedMessage.status != newStatus ||
                cachedMessage.updatedAt != newUpdatedAt) {
              hasChanges = true;
              debugPrint('🔄 Real-time change detected in message: $id');
              break;
            }
          }

          if (!hasChanges) {
            debugPrint(
                '🔄 Skipping redundant real-time update - no changes detected in ${data.length} messages');
            return;
          }
        }
      }

      debugPrint(
          '🔄 Processing real-time update with ${data.length} messages (changes detected)');

      // Delegate to the original method for actual processing
      await _handleMessagesUpdate(conversationId, data);
    } catch (e) {
      debugPrint('❌ Error in smart messages update: $e');
      // Fallback to original method
      await _handleMessagesUpdate(conversationId, data);
    }
  }

  /// Handle messages update from real-time stream
  Future<void> _handleMessagesUpdate(
      String conversationId, List<Map<String, dynamic>> data) async {
    try {
      if (_verboseLogging) {
        debugPrint('📨 Received messages update: ${data.length} messages');
      }

      // CROSS-USER REAL-TIME FIX: Separate new messages from existing ones for faster processing
      final cachedMessages = _messagesCache[conversationId] ?? [];
      final cachedIds = cachedMessages.map((m) => m.id).toSet();

      final newMessages = <Map<String, dynamic>>[];
      final existingMessages = <Map<String, dynamic>>[];

      for (final messageData in data) {
        final messageId = messageData['id'] as String;
        if (cachedIds.contains(messageId)) {
          existingMessages.add(messageData);
        } else {
          newMessages.add(messageData);
        }
      }

      // REAL-TIME OPTIMIZATION: Process new messages first for instant delivery
      final List<Message> allProcessedMessages = [];

      if (newMessages.isNotEmpty) {
        debugPrint(
            '🚀 REAL-TIME: Fast-processing ${newMessages.length} new messages for instant delivery');
        final newProcessedMessages =
            await _processMessagesOptimized(newMessages, isNewMessage: true);
        allProcessedMessages.addAll(newProcessedMessages);

        // Immediately deliver new messages to UI while processing existing ones
        final quickMergedMessages = [
          ...cachedMessages,
          ...newProcessedMessages
        ];
        quickMergedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _optimisticUI.mergeServerMessages(conversationId, quickMergedMessages);
        debugPrint(
            '⚡ REAL-TIME: Delivered ${newMessages.length} new messages instantly');
      }

      // Process existing messages (updates/status changes) in background
      if (existingMessages.isNotEmpty) {
        final existingProcessedMessages = await _processMessagesOptimized(
            existingMessages,
            isNewMessage: false);
        allProcessedMessages.addAll(existingProcessedMessages);
      }

      // Final merge with all processed messages
      final finalMessages = [...cachedMessages];
      for (final processedMessage in allProcessedMessages) {
        final existingIndex =
            finalMessages.indexWhere((m) => m.id == processedMessage.id);
        if (existingIndex != -1) {
          finalMessages[existingIndex] = processedMessage;
        } else {
          finalMessages.add(processedMessage);
        }
      }

      // Sort chronologically
      finalMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      // Route all message updates through optimistic UI to maintain consistent ordering
      _optimisticUI.mergeServerMessages(conversationId, finalMessages);

      // Update cache but don't directly emit to stream - let optimistic UI handle it
      _messagesCache[conversationId] = finalMessages;

      // Don't emit directly to _messagesController - optimistic UI will handle UI updates
      // _messagesController.add(messages); // Removed to prevent race conditions

      // Optimized cache warming - messages are already processed during decryption
      // Skip redundant cache warming since messages are cached during processing
      // _messageCache.warmCache(messages); // Removed to prevent duplicate caching
    } catch (e) {
      debugPrint('❌ Error handling messages update: $e');
    }
  }

  /// Optimized message processing for real-time delivery
  Future<List<Message>> _processMessagesOptimized(
      List<Map<String, dynamic>> messagesData,
      {required bool isNewMessage}) async {
    final List<Message> messages = [];

    for (final messageData in messagesData) {
      // Map database response to expected format with null safety
      final now = DateTime.now().toIso8601String();
      final mappedMessageData = {
        'id': messageData['id'] ?? '',
        'conversationId': messageData['conversation_id'] ?? '',
        'senderId': messageData['sender_id'] ?? '',
        'messageType': messageData['message_type'] ?? 'text',
        'content': messageData['content'] ?? '',
        'isDeleted': messageData['is_deleted'] ?? false,
        'isEdited': messageData['is_edited'] ?? false,
        'createdAt': messageData['created_at'] ?? now,
        'updatedAt': messageData['updated_at'] ?? now,
        'editedAt': messageData['edited_at'],
        'expiresAt': messageData['expires_at'],
        'status': messageData['status'] ?? 'sent',
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

      // Optimized message processing with smart caching
      Message processedMessage = message;

      // Check if message is already processed to prevent duplicates
      final cachedMessage = _messageCache.getCachedProcessedMessage(message.id);
      if (cachedMessage != null) {
        processedMessage = cachedMessage;
      } else if (message.isEncrypted) {
        try {
          // Check cache first for instant performance
          final cachedContent =
              _messageCache.getCachedDecryptedContent(message.id);
          if (cachedContent != null) {
            processedMessage = message.copyWith(
              content: cachedContent,
              isEncrypted: false,
            );
          } else {
            // REAL-TIME OPTIMIZATION: For new messages, prioritize speed
            if (isNewMessage) {
              debugPrint(
                  '🔐 REAL-TIME: Fast-decrypting new message ${message.id}');
            }

            // Use cached key retrieval to avoid repeated database calls
            final conversationKey = await _keyCache.getConversationKey(
              message.conversationId,
              () => _getConversationKeyForDecryption(message.conversationId),
            );

            // Decrypt in background isolate to prevent UI blocking
            final decryptedContent = await _encryptionIsolate.decryptMessage(
              encryptedContent: message.content,
              conversationKey: conversationKey,
              encryptionMetadata: message.encryptionMetadata ?? {},
            );

            processedMessage = message.copyWith(
              content: decryptedContent,
              isEncrypted: false,
            );

            // Cache the decrypted content for future use
            _messageCache.cacheDecryptedContent(message.id, decryptedContent);
          }

          // Cache the processed message
          _messageCache.cacheProcessedMessage(message.id, processedMessage);
        } catch (e) {
          debugPrint('❌ Failed to decrypt message ${message.id}: $e');
          processedMessage = message.copyWith(
            content: '[Encrypted message - decryption failed]',
          );
        }
      } else {
        // Cache non-encrypted messages
        _messageCache.cacheProcessedMessage(message.id, message);
      }

      // REAL-TIME OPTIMIZATION: Load sender profile in parallel for new messages
      if (isNewMessage) {
        // Load sender profile data in background to avoid blocking
        _getSenderProfile(message.senderId).then((senderProfile) {
          if (senderProfile != null) {
            final updatedMessage = processedMessage.copyWith(
              senderName: senderProfile.displayName ?? senderProfile.username,
              senderAvatarUrl: senderProfile.avatarUrl,
            );
            // Update cache with profile data
            _messageCache.cacheProcessedMessage(message.id, updatedMessage);
          }
        });
      } else {
        // For existing messages, load profile synchronously
        final senderProfile = await _getSenderProfile(message.senderId);
        processedMessage = processedMessage.copyWith(
          senderName: senderProfile?.displayName ?? senderProfile?.username,
          senderAvatarUrl: senderProfile?.avatarUrl,
        );
      }

      // Load reply-to message if exists (background for new messages)
      if (message.replyToId != null) {
        if (isNewMessage) {
          // Load reply-to message in background for new messages
          _getMessage(message.replyToId!).then((replyToMessage) {
            if (replyToMessage != null) {
              final updatedMessage =
                  processedMessage.copyWith(replyToMessage: replyToMessage);
              _messageCache.cacheProcessedMessage(message.id, updatedMessage);
            }
          });
        } else {
          final replyToMessage = await _getMessage(message.replyToId!);
          processedMessage =
              processedMessage.copyWith(replyToMessage: replyToMessage);
        }
      }

      messages.add(processedMessage);
    }

    return messages;
  }

  /// Get messages for conversation with progressive loading (public method for chat screen)
  Future<List<Message>> getMessagesForConversation(String conversationId,
      {int limit = 50,
      int offset = 0,
      bool useProgressiveLoading = true}) async {
    _startPerformanceTimer('getMessagesForConversation');

    try {
      debugPrint('📥 🔥 GET MESSAGES: ===== LOADING MESSAGES =====');
      debugPrint('📥 🔥 GET MESSAGES: Conversation: $conversationId');
      debugPrint('📥 🔥 GET MESSAGES: Limit: $limit, Offset: $offset');
      debugPrint(
          '📥 🔥 GET MESSAGES: UseProgressiveLoading: $useProgressiveLoading');

      // Use progressive loading for instant UI response
      if (useProgressiveLoading && offset == 0) {
        final messages = await _progressiveLoader.loadMessagesProgressive(
          conversationId,
          onBackgroundUpdate: (freshMessages) {
            // Route all updates through optimistic UI to maintain consistent ordering
            _optimisticUI.mergeServerMessages(conversationId, freshMessages);

            // Update cache but let optimistic UI handle UI updates
            _messagesCache[conversationId] = freshMessages;

            // Don't emit directly to stream - optimistic UI will handle it
            // _messagesController.add(freshMessages); // Removed to prevent race conditions

            debugPrint(
                '⚡ UI updated instantly with ${freshMessages.length} fresh messages');
          },
        );

        // Update the conversation service's message cache
        _messagesCache[conversationId] = messages;

        // Don't emit directly to stream - optimistic UI handles all UI updates
        // _messagesController.add(messages); // Removed to prevent race conditions

        debugPrint(
            '📥 🔥 GET MESSAGES: Progressive loading returned ${messages.length} messages');
        if (messages.isNotEmpty) {
          debugPrint(
              '📥 🔥 GET MESSAGES: First: ${messages.first.createdAt} (${messages.first.id})');
          debugPrint(
              '📥 🔥 GET MESSAGES: Last: ${messages.last.createdAt} (${messages.last.id})');
        }

        _stopPerformanceTimer('getMessagesForConversation');
        return messages;
      }

      // Fallback to traditional loading for pagination
      final response = await _supabase
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true)
          .range(offset, offset + limit - 1);

      // Cast the response to the expected type
      final List<Map<String, dynamic>> messagesData =
          (response as List<dynamic>).cast<Map<String, dynamic>>();

      // Process messages with decryption and sender info
      final List<Message> messages = [];
      for (final messageData in messagesData) {
        final now = DateTime.now().toIso8601String();
        final mappedMessageData = {
          'id': messageData['id'] ?? '',
          'conversationId': messageData['conversation_id'] ?? '',
          'senderId': messageData['sender_id'] ?? '',
          'messageType': messageData['message_type'] ?? 'text',
          'content': messageData['content'] ?? '',
          'isDeleted': messageData['is_deleted'] ?? false,
          'isEdited': messageData['is_edited'] ?? false,
          'createdAt': messageData['created_at'] ?? now,
          'updatedAt': messageData['updated_at'] ?? now,
          'editedAt': messageData['edited_at'],
          'expiresAt': messageData['expires_at'],
          'status': messageData['status'] ?? 'sent',
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

        // Optimized message processing with smart caching
        Message processedMessage = message;

        // Check if message is already processed to prevent duplicates
        final cachedMessage =
            _messageCache.getCachedProcessedMessage(message.id);
        if (cachedMessage != null) {
          processedMessage = cachedMessage;
        } else if (message.isEncrypted) {
          try {
            // Check cache first for instant performance
            final cachedContent =
                _messageCache.getCachedDecryptedContent(message.id);
            if (cachedContent != null) {
              processedMessage = message.copyWith(
                content: cachedContent,
                isEncrypted: false,
              );
            } else {
              // Use cached key retrieval to avoid repeated database calls
              final conversationKey = await _keyCache.getConversationKey(
                message.conversationId,
                () => _getConversationKeyForDecryption(message.conversationId),
              );

              // Decrypt in background isolate to prevent UI blocking
              final decryptedContent = await _encryptionIsolate.decryptMessage(
                encryptedContent: message.content,
                conversationKey: conversationKey,
                encryptionMetadata: message.encryptionMetadata ?? {},
              );

              processedMessage = message.copyWith(
                content: decryptedContent,
                isEncrypted: false,
              );

              // Cache the decrypted content for future use
              _messageCache.cacheDecryptedContent(message.id, decryptedContent);
            }

            // Cache the processed message
            _messageCache.cacheProcessedMessage(message.id, processedMessage);
          } catch (e) {
            debugPrint('❌ Failed to decrypt message ${message.id}: $e');
            processedMessage = message.copyWith(
              content: '[Encrypted message - decryption failed]',
            );
          }
        } else {
          // Cache non-encrypted messages
          _messageCache.cacheProcessedMessage(message.id, message);
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

      debugPrint('✅ Loaded and processed ${messages.length} messages');
      return messages;
    } catch (e) {
      debugPrint('❌ Error loading messages: $e');
      return [];
    }
  }

  /// Load messages for conversation (private method for stream updates)
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

  /// Mark messages as read with instant UI updates and non-blocking server sync
  Future<void> markMessagesAsRead(String conversationId) async {
    if (_currentUserId == null) {
      debugPrint('❌ Cannot mark messages as read: No current user');
      return;
    }

    _startPerformanceTimer('MarkMessagesAsRead_UIUpdate');
    debugPrint(
        '📖 Starting markMessagesAsRead for conversation: $conversationId');
    debugPrint('👤 Current user ID: $_currentUserId');

    // REAL-TIME READ STATUS FIX: Get unread message IDs from other users
    final unreadMessageIds = <String>[];
    final cachedMessages = _messagesCache[conversationId] ?? [];

    for (final message in cachedMessages) {
      final isFromCurrentUser = message.senderId == _currentUserId;
      final isFromOther = !isFromCurrentUser;
      final isAlreadyRead = message.status == MessageStatus.read;

      // Debug: Show status of all messages from other users
      if (isFromOther) {
        debugPrint(
            '🔍 Message from other user: ${message.id.substring(0, 8)}... status=${message.status}, sender=${message.senderId.substring(0, 8)}...');
      }

      // Only mark messages from other users that are not already read
      if (isFromOther && !isAlreadyRead) {
        unreadMessageIds.add(message.id);
        debugPrint(
            '✅ Added unread message: ${message.id.substring(0, 8)}... status=${message.status}');
      }
    }

    debugPrint(
        '📖 Found ${unreadMessageIds.length} unread messages to mark as read: $unreadMessageIds');

    // Update UI instantly (0ms perceived delay) - completely non-blocking
    _optimisticUI.updateReadStatusInstantly(conversationId, unreadMessageIds);
    _stopPerformanceTimer('MarkMessagesAsRead_UIUpdate');
    debugPrint(
        '⚡ Updated read status instantly for ${unreadMessageIds.length} messages (0ms perceived delay)');

    // Perform server sync in background (completely non-blocking)
    Future.microtask(() => _performMarkAsReadServerSync(conversationId));

    // CRITICAL FIX: Immediately refresh unread count to update conversation list
    Future.microtask(() => _refreshConversationUnreadCount(conversationId));
  }

  /// Perform server sync for mark-as-read in background (non-blocking)
  void _performMarkAsReadServerSync(String conversationId) {
    _startPerformanceTimer('MarkMessagesAsRead_ServerSync');

    // Run in background without blocking UI
    Future(() async {
      try {
        await _networkService.executeWithRetry(() async {
          final timestamp = DateTime.now().toIso8601String();
          debugPrint(
              '🔄 Background sync: Updating last_read_at for user $_currentUserId in conversation $conversationId');

          // Update last read timestamp for current user
          final participantResult = await _supabase
              .from('conversation_participants')
              .update({'last_read_at': timestamp})
              .eq('conversation_id', conversationId)
              .eq('user_id', _currentUserId)
              .select();

          debugPrint(
              '📝 Participant update result: ${participantResult.length} rows updated');

          // Update message status to read for messages from other users
          final messagesResult = await _supabase
              .from('messages')
              .update({
                'status': 'read',
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('conversation_id', conversationId)
              .neq('sender_id', _currentUserId)
              .in_('status', ['sent', 'delivered'])
              .select();

          debugPrint(
              '📝 Messages update result: ${messagesResult.length} messages marked as read');

          // REAL-TIME FIX: Force real-time notification for read status updates
          if (messagesResult.isNotEmpty) {
            debugPrint(
                '🔔 Triggering real-time read status updates for ${messagesResult.length} messages');

            // Update local cache immediately to ensure UI consistency
            for (final messageData in messagesResult) {
              final messageId = messageData['id'] as String;
              _messageStatusService.updateMessageStatus(
                messageId,
                MessageStatus.read,
                optimistic: false, // Use server-confirmed status
              );
            }
          }
        }, operationName: 'Mark messages as read (background)');

        _stopPerformanceTimer('MarkMessagesAsRead_ServerSync');
        debugPrint(
            '✅ Background sync completed for conversation: $conversationId');

        // Trigger a refresh of the conversation to update unread count
        _refreshConversationUnreadCount(conversationId);
      } catch (e) {
        _stopPerformanceTimer('MarkMessagesAsRead_ServerSync');
        debugPrint('❌ Background sync error for marking messages as read: $e');
        // Add to offline queue for retry when network is restored
        _scheduleRetryMarkAsRead(conversationId);
      }
    });
  }

  /// Refresh unread count for a specific conversation
  void _refreshConversationUnreadCount(String conversationId) {
    // Trigger a background refresh of the conversation's unread count
    _getUnreadMessageCount(conversationId).then((count) {
      debugPrint('🔄 Refreshed unread count for $conversationId: $count');
      // Update the cached conversation if it exists
      final cachedConversations = _conversationsCache[_currentUserId!];
      if (cachedConversations != null) {
        final updatedConversations = cachedConversations.map((conv) {
          if (conv.id == conversationId) {
            return conv.copyWith(unreadCount: count);
          }
          return conv;
        }).toList();
        _conversationsCache[_currentUserId!] = updatedConversations;

        // CRITICAL FIX: Emit to stream to update unread indicators immediately
        // This is safe because we're only updating unread count, not reloading messages
        _conversationsController.add(updatedConversations);

        debugPrint(
            '🔄 Updated conversation unread count and emitted to UI: $count');
      }
    }).catchError((e) {
      debugPrint('❌ Error refreshing unread count: $e');
    });
  }

  /// Schedule retry for marking messages as read
  void _scheduleRetryMarkAsRead(String conversationId) {
    Timer(const Duration(seconds: 5), () {
      if (_networkService.isOnline) {
        markMessagesAsRead(conversationId);
      }
    });
  }

  /// Set typing status with proper constraint handling
  Future<void> setTypingStatus(String conversationId, bool isTyping) async {
    if (_currentUserId == null) return;

    try {
      await _networkService.executeWithRetry(() async {
        // First, try to update existing record
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
        if (updateResult.isEmpty) {
          await _supabase.from('typing_status').insert({
            'conversation_id': conversationId,
            'user_id': _currentUserId,
            'is_typing': isTyping,
            'last_updated': DateTime.now().toIso8601String(),
          });
        }
      }, operationName: 'Set typing status');

      debugPrint(
          '✅ Updated typing status: $isTyping for conversation: $conversationId');
    } catch (e) {
      debugPrint('❌ Error setting typing status: $e');

      // Handle constraint violation specifically
      if (e
          .toString()
          .contains('duplicate key value violates unique constraint')) {
        debugPrint(
            '🔄 Constraint violation detected, retrying with update only...');
        try {
          // Force update the existing record
          await _supabase
              .from('typing_status')
              .update({
                'is_typing': isTyping,
                'last_updated': DateTime.now().toIso8601String(),
              })
              .eq('conversation_id', conversationId)
              .eq('user_id', _currentUserId);
          debugPrint('✅ Typing status updated after constraint violation');
        } catch (e2) {
          debugPrint(
              '❌ Failed to update typing status after constraint violation: $e2');
        }
      }
    }
  }

  /// REAL-TIME READ STATUS FIX: Subscribe to message status updates
  void _subscribeToMessageStatusUpdates(String conversationId) {
    try {
      debugPrint(
          '🔔 Setting up real-time message status subscription for: $conversationId');

      // Subscribe to message updates specifically for status changes
      _supabase.channel('message_status_$conversationId').on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(
          event: 'UPDATE',
          schema: 'public',
          table: 'messages',
          filter: 'conversation_id=eq.$conversationId',
        ),
        (payload, [ref]) {
          debugPrint('🔔 Real-time message status update received');

          if (payload['new'] != null) {
            final messageData = payload['new'] as Map<String, dynamic>;
            final messageId = messageData['id'] as String;
            final statusStr = messageData['status'] as String?;

            if (statusStr != null) {
              // Convert string status to MessageStatus enum
              MessageStatus? status;
              switch (statusStr.toLowerCase()) {
                case 'sent':
                  status = MessageStatus.sent;
                  break;
                case 'delivered':
                  status = MessageStatus.delivered;
                  break;
                case 'read':
                  status = MessageStatus.read;
                  break;
                case 'failed':
                  status = MessageStatus.failed;
                  break;
              }

              if (status != null) {
                // PERFORMANCE FIX: Reduce verbose logging and prevent duplicate updates
                final updateKey = '${messageId}_${status.name}';

                if (!_recentStatusUpdates.contains(updateKey)) {
                  _recentStatusUpdates.add(updateKey);

                  // Clean up old entries to prevent memory leaks (keep last 50)
                  if (_recentStatusUpdates.length > 50) {
                    _recentStatusUpdates.clear();
                  }

                  // Update message status service for immediate UI update
                  _messageStatusService.updateMessageStatus(
                    messageId,
                    status,
                    optimistic: false, // This is server-confirmed
                  );

                  // Only log significant status changes to reduce noise
                  if (status == MessageStatus.read ||
                      status == MessageStatus.failed) {
                    debugPrint('🔔 Message $messageId status: $status');
                  }
                }
              }
            }
          }
        },
      ).subscribe();

      debugPrint(
          '✅ Real-time message status subscription active for: $conversationId');
    } catch (e) {
      debugPrint('❌ Error setting up message status subscription: $e');
    }
  }

  /// Trigger conversation refresh for real-time updates
  void _triggerConversationRefresh(String conversationId) {
    try {
      debugPrint('🔄 Triggering conversation refresh for: $conversationId');

      // Simply trigger a message status update notification
      // The UI will automatically refresh when it receives the status update
      _messageStatusController.add('status_updated_$conversationId');
    } catch (e) {
      debugPrint('❌ Error triggering conversation refresh: $e');
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
      final String fileName = '${_uuid.v4()}${_getFileExtension(file.path)}';
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

  /// Get file extension from path
  String _getFileExtension(String filePath) {
    final lastDot = filePath.lastIndexOf('.');
    return lastDot != -1 ? filePath.substring(lastDot) : '';
  }

  /// Get mime type from file path using mime package
  String _getMimeType(String filePath) {
    return lookupMimeType(filePath) ?? 'application/octet-stream';
  }

  /// Unsubscribe from current conversation
  Future<void> unsubscribeFromMessages() async {
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;
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

    // Cancel timers
    _offlineQueueSaveTimer?.cancel();
    _conversationUpdateTimer?.cancel();

    // Save any pending offline queue changes
    if (_offlineQueueDirty) {
      _saveOfflineQueue();
    }

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
    _lastMessageCache.clear();
    _lastMessageCacheTime.clear();

    // Dispose other services
    _locationService.dispose();
  }

  /// Get conversation key for decryption (wrapper for key management service)
  Future<String> _getConversationKeyForDecryption(String conversationId) async {
    try {
      // Try to determine conversation type from ID or database
      final conversation = await _getConversationById(conversationId);

      if (conversation?.type == ConversationType.directMessage) {
        // For direct messages, extract other user ID
        final participants = await _getConversationParticipants(conversationId);
        final otherUser = participants.firstWhere(
          (p) => p.userId != _currentUserId,
          orElse: () => throw Exception('No other user found in DM'),
        );

        final conversationKey = await _keyManagementService
            .getOrCreateDirectMessageKey(otherUser.userId,
                actualConversationId: conversationId);

        if (conversationKey == null) {
          throw Exception('Failed to get DM conversation key');
        }

        return base64Encode(conversationKey.symmetricKey);
      } else {
        // For pulse chats
        final conversationKey =
            await _keyManagementService.getOrCreatePulseChatKey(conversationId);

        if (conversationKey == null) {
          throw Exception('Failed to get pulse conversation key');
        }

        return base64Encode(conversationKey.symmetricKey);
      }
    } catch (e) {
      debugPrint('❌ Error getting conversation key for decryption: $e');
      rethrow;
    }
  }

  /// Get conversation by ID (helper method)
  Future<Conversation?> _getConversationById(String conversationId) async {
    try {
      debugPrint('🔍 Getting conversation by ID: $conversationId');
      final response = await _supabase
          .from('conversations')
          .select()
          .eq('id', conversationId)
          .maybeSingle();

      debugPrint('🔍 Raw conversation response: $response');
      debugPrint('🔍 Response type: ${response.runtimeType}');

      if (response != null) {
        // Safely cast the response to Map<String, dynamic>
        Map<String, dynamic> conversationData;

        if (response is Map<String, dynamic>) {
          conversationData = response;
        } else {
          conversationData = Map<String, dynamic>.from(response as Map);
        }

        debugPrint('🔍 Conversation data: $conversationData');
        debugPrint('🔍 Conversation type: ${conversationData['type']}');

        return Conversation.fromJson(conversationData);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error getting conversation by ID: $e');
      debugPrint('📍 Stack trace: $stackTrace');
    }
    return null;
  }

  /// Get unread messages for a conversation (helper method for optimistic UI)
  Future<List<Message>> _getUnreadMessagesForConversation(
      String conversationId) async {
    try {
      final response = await _supabase
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .neq('sender_id', _currentUserId)
          .in_('status', ['sent', 'delivered']).order('created_at',
              ascending: false);

      final List<dynamic> responseList = response as List<dynamic>;
      return responseList
          .map((data) => Message.fromJson(data as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ Error getting unread messages: $e');
      return [];
    }
  }
}
