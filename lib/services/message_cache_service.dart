import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/message.dart';

/// High-performance message cache service for instant chat responsiveness
///
/// This service provides:
/// - Decrypted message content caching to avoid re-decryption
/// - LRU cache with automatic memory management
/// - Instant message retrieval for UI updates
/// - Background cache warming for better performance
class MessageCacheService {
  static final MessageCacheService _instance = MessageCacheService._internal();
  factory MessageCacheService() => _instance;
  MessageCacheService._internal();

  // Cache configuration for optimal performance
  static const int _maxCacheSize = 1000; // Cache up to 1000 messages
  static const Duration _cacheExpiry = Duration(hours: 2); // 2 hour expiry
  static const Duration _backgroundCleanupInterval = Duration(minutes: 10);

  // Decrypted message content cache (messageId -> decrypted content)
  final Map<String, _CachedMessage> _decryptedContentCache = {};

  // Processed message cache (messageId -> processed Message object)
  final Map<String, _CachedMessage> _processedMessageCache = {};

  // Conversation-level message tracking for progressive loading
  final Map<String, List<String>> _conversationMessages = {};
  final Map<String, DateTime> _conversationLastAccess = {};

  // LRU tracking for cache eviction
  final List<String> _lruOrder = [];

  // Background cleanup timer
  Timer? _cleanupTimer;

  // Performance metrics
  int _cacheHits = 0;
  int _cacheMisses = 0;

  // Logging optimization - reduce verbose logging during normal operation
  int _logCounter = 0;
  static const int _logInterval = 10; // Log every 10th cache hit

  // Track processed messages to prevent duplicates
  final Set<String> _processedMessageIds = {};

  // Reduce verbose logging for performance
  static const bool _verboseLogging = false;

  /// Initialize the cache service
  void initialize() {
    if (_verboseLogging) {
      debugPrint('🚀 Initializing MessageCacheService for instant performance');
    }

    // Start background cleanup
    _cleanupTimer = Timer.periodic(_backgroundCleanupInterval, (_) {
      _performBackgroundCleanup();
    });

    if (_verboseLogging) {
      debugPrint('✅ MessageCacheService initialized');
    }
  }

  /// Dispose the cache service
  void dispose() {
    _cleanupTimer?.cancel();
    _decryptedContentCache.clear();
    _processedMessageCache.clear();
    _lruOrder.clear();
    debugPrint('🧹 MessageCacheService disposed');
  }

  /// Get cached decrypted content for a message
  /// Returns null if not cached or expired
  String? getCachedDecryptedContent(String messageId) {
    final cached = _decryptedContentCache[messageId];
    if (cached == null) {
      _cacheMisses++;
      return null;
    }

    // Check if expired
    if (DateTime.now().difference(cached.timestamp) > _cacheExpiry) {
      _decryptedContentCache.remove(messageId);
      _lruOrder.remove(messageId);
      _cacheMisses++;
      return null;
    }

    // Update LRU order
    _updateLRU(messageId);
    _cacheHits++;

    // Reduced logging - only log during debug mode or for performance tracking
    if (kDebugMode && _shouldLogCacheHit()) {
      debugPrint('⚡ Cache HIT for message $messageId (decrypted content)');
    }
    return cached.content;
  }

  /// Cache decrypted content for a message (with duplicate prevention)
  void cacheDecryptedContent(String messageId, String decryptedContent) {
    // Prevent duplicate caching
    if (_decryptedContentCache.containsKey(messageId)) {
      return; // Already cached, skip
    }

    _decryptedContentCache[messageId] = _CachedMessage(
      content: decryptedContent,
      timestamp: DateTime.now(),
    );

    _updateLRU(messageId);
    _enforceMaxCacheSize();

    // Reduced logging for performance
    if (_shouldLogCacheOperation()) {
      debugPrint('💾 Cached decrypted content for message $messageId');
    }
  }

  /// Get cached processed message
  /// Returns null if not cached or expired
  Message? getCachedProcessedMessage(String messageId) {
    final cached = _processedMessageCache[messageId];
    if (cached == null) {
      _cacheMisses++;
      return null;
    }

    // Check if expired
    if (DateTime.now().difference(cached.timestamp) > _cacheExpiry) {
      _processedMessageCache.remove(messageId);
      _lruOrder.remove(messageId);
      _cacheMisses++;
      return null;
    }

    // Update LRU order
    _updateLRU(messageId);
    _cacheHits++;

    // Reduced logging for performance
    if (_shouldLogCacheHit()) {
      debugPrint('⚡ Cache HIT for message $messageId (processed message)');
    }
    return cached.message;
  }

  /// Cache processed message (with status update support)
  void cacheProcessedMessage(String messageId, Message processedMessage) {
    final existingCached = _processedMessageCache[messageId];

    // Allow updates if:
    // 1. Message not cached yet, OR
    // 2. Status has changed (important for sending -> sent transitions)
    if (existingCached == null ||
        existingCached.message?.status != processedMessage.status) {
      _processedMessageCache[messageId] = _CachedMessage(
        message: processedMessage,
        timestamp: DateTime.now(),
      );

      _updateLRU(messageId);
      _enforceMaxCacheSize();

      // Enhanced logging for status updates
      if (_shouldLogCacheOperation()) {
        if (existingCached != null) {
          debugPrint(
              '💾 Updated cached message $messageId status: ${existingCached.message?.status} -> ${processedMessage.status}');
        } else {
          debugPrint(
              '💾 Cached processed message $messageId with status: ${processedMessage.status}');
        }
      }
    }
  }

  /// Optimized cache warming - only cache uncached messages
  void warmCache(List<Message> messages) {
    if (messages.isEmpty) return;

    // Pre-filter to only uncached messages for maximum efficiency
    final uncachedMessages = messages
        .where((msg) =>
            !_processedMessageCache.containsKey(msg.id) &&
            !_decryptedContentCache.containsKey(msg.id))
        .toList();

    if (uncachedMessages.isEmpty) {
      // All messages already cached, skip warming
      return;
    }

    int newlyCached = 0;

    for (final message in uncachedMessages) {
      if (!message.isEncrypted) {
        // Cache already decrypted messages (without duplicate check since pre-filtered)
        _cacheDecryptedContentDirect(message.id, message.content);
      }
      _cacheProcessedMessageDirect(message.id, message);
      newlyCached++;
    }

    // Only log if significant caching occurred and at intervals
    if (newlyCached > 5 && _shouldLogCacheOperation()) {
      debugPrint(
          '🔥 Cache warmed: $newlyCached new messages (${messages.length} total)');
    }
  }

  /// Clear cache for a specific conversation
  void clearConversationCache(String conversationId) {
    final messagesToRemove = <String>[];

    for (final entry in _processedMessageCache.entries) {
      if (entry.value.message?.conversationId == conversationId) {
        messagesToRemove.add(entry.key);
      }
    }

    for (final messageId in messagesToRemove) {
      _decryptedContentCache.remove(messageId);
      _processedMessageCache.remove(messageId);
      _lruOrder.remove(messageId);
    }

    debugPrint(
        '🧹 Cleared cache for conversation $conversationId (${messagesToRemove.length} messages)');
  }

  /// Get cache performance statistics
  Map<String, dynamic> getPerformanceStats() {
    final totalRequests = _cacheHits + _cacheMisses;
    final hitRate =
        totalRequests > 0 ? (_cacheHits / totalRequests * 100) : 0.0;

    return {
      'cache_hits': _cacheHits,
      'cache_misses': _cacheMisses,
      'hit_rate_percent': hitRate.toStringAsFixed(1),
      'cached_messages': _decryptedContentCache.length,
      'processed_messages': _processedMessageCache.length,
      'total_cache_size':
          _decryptedContentCache.length + _processedMessageCache.length,
    };
  }

  /// Update LRU order for cache eviction
  void _updateLRU(String messageId) {
    _lruOrder.remove(messageId);
    _lruOrder.add(messageId);
  }

  /// Enforce maximum cache size using LRU eviction
  void _enforceMaxCacheSize() {
    while (_lruOrder.length > _maxCacheSize) {
      final oldestMessageId = _lruOrder.removeAt(0);
      _decryptedContentCache.remove(oldestMessageId);
      _processedMessageCache.remove(oldestMessageId);
    }
  }

  /// Perform background cleanup of expired entries
  void _performBackgroundCleanup() {
    final now = DateTime.now();
    final expiredIds = <String>[];

    // Find expired entries
    for (final entry in _decryptedContentCache.entries) {
      if (now.difference(entry.value.timestamp) > _cacheExpiry) {
        expiredIds.add(entry.key);
      }
    }

    // Remove expired entries
    for (final id in expiredIds) {
      _decryptedContentCache.remove(id);
      _processedMessageCache.remove(id);
      _lruOrder.remove(id);
    }

    if (expiredIds.isNotEmpty && _shouldLogCacheOperation()) {
      debugPrint(
          '🧹 Background cleanup removed ${expiredIds.length} expired cache entries');
    }
  }

  /// Optimized logging - reduce verbose logs during normal operation
  bool _shouldLogCacheHit() {
    _logCounter++;
    return _logCounter % _logInterval == 0; // Log every 10th cache hit
  }

  /// Optimized logging for cache operations
  bool _shouldLogCacheOperation() {
    return kDebugMode &&
        (_cacheHits + _cacheMisses) % 100 == 0; // Log every 100 operations
  }

  /// Check if message is already processed to prevent duplicates
  bool isMessageProcessed(String messageId) {
    return _processedMessageCache.containsKey(messageId) ||
        _decryptedContentCache.containsKey(messageId);
  }

  /// Batch cache check for multiple messages
  List<String> getUncachedMessageIds(List<String> messageIds) {
    return messageIds.where((id) => !isMessageProcessed(id)).toList();
  }

  /// Cache messages for a specific conversation
  void cacheConversationMessages(
      String conversationId, List<Message> messages) {
    final messageIds = messages.map((m) => m.id).toList();
    _conversationMessages[conversationId] = messageIds;
    _conversationLastAccess[conversationId] = DateTime.now();

    // Cache individual messages
    for (final message in messages) {
      if (!_processedMessageCache.containsKey(message.id)) {
        _cacheProcessedMessageDirect(message.id, message);
      }
    }

    if (_shouldLogCacheOperation()) {
      debugPrint(
          '💾 Cached conversation messages: $conversationId (${messages.length} messages)');
    }
  }

  /// Get cached message IDs for a conversation
  List<String> getConversationMessageIds(String conversationId) {
    _conversationLastAccess[conversationId] = DateTime.now();
    return _conversationMessages[conversationId] ?? [];
  }

  /// Predictive cache warming for likely-to-be-opened conversations
  void warmConversationsPredictive(List<String> conversationIds) {
    for (final conversationId in conversationIds) {
      final lastAccess = _conversationLastAccess[conversationId];
      if (lastAccess == null ||
          DateTime.now().difference(lastAccess) > const Duration(hours: 1)) {
        // Conversation hasn't been accessed recently, warm it
        _warmConversationBackground(conversationId);
      }
    }
  }

  /// Direct cache methods for performance (skip duplicate checks)
  void _cacheDecryptedContentDirect(String messageId, String decryptedContent) {
    _decryptedContentCache[messageId] = _CachedMessage(
      content: decryptedContent,
      timestamp: DateTime.now(),
    );
    _updateLRU(messageId);
    _enforceMaxCacheSize();
  }

  void _cacheProcessedMessageDirect(
      String messageId, Message processedMessage) {
    // Always update for direct cache operations (used during warming)
    _processedMessageCache[messageId] = _CachedMessage(
      message: processedMessage,
      timestamp: DateTime.now(),
    );
    _updateLRU(messageId);
    _enforceMaxCacheSize();
  }

  /// Background conversation warming (placeholder for future implementation)
  void _warmConversationBackground(String conversationId) {
    // This would integrate with the progressive message loader
    // to pre-load conversation messages in background
    Future.microtask(() {
      debugPrint('🔥 Background warming conversation: $conversationId');
      // Implementation would depend on integration with ConversationService
    });
  }
}

/// Internal cached message structure
class _CachedMessage {
  final String? content;
  final Message? message;
  final DateTime timestamp;

  _CachedMessage({
    this.content,
    this.message,
    required this.timestamp,
  });
}
