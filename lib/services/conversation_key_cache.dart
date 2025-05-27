import 'dart:async';
import 'package:flutter/foundation.dart';

/// High-performance conversation key cache to eliminate repeated database calls
class ConversationKeyCache {
  static ConversationKeyCache? _instance;
  static ConversationKeyCache get instance =>
      _instance ??= ConversationKeyCache._();

  ConversationKeyCache._();

  // In-memory cache for conversation keys
  final Map<String, String> _keyCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, Completer<String>> _pendingRequests = {};

  // Cache configuration
  static const Duration _cacheExpiry = Duration(hours: 1);
  static const int _maxCacheSize = 100;

  /// Get conversation key with aggressive caching
  Future<String> getConversationKey(
    String conversationId,
    Future<String> Function() keyRetriever,
  ) async {
    // Check if key is already cached and valid
    final cachedKey = _getCachedKey(conversationId);
    if (cachedKey != null) {
      debugPrint('⚡ Using cached conversation key for: $conversationId');
      return cachedKey;
    }

    // Check if there's already a pending request for this key
    final pendingRequest = _pendingRequests[conversationId];
    if (pendingRequest != null) {
      debugPrint('⏳ Waiting for pending key request: $conversationId');
      return pendingRequest.future;
    }

    // Create new request
    final completer = Completer<String>();
    _pendingRequests[conversationId] = completer;

    try {
      debugPrint('🔑 Fetching conversation key from database: $conversationId');
      final key = await keyRetriever();

      // Cache the key
      _cacheKey(conversationId, key);

      // Complete all waiting requests
      completer.complete(key);
      _pendingRequests.remove(conversationId);

      debugPrint('✅ Cached conversation key: $conversationId');
      return key;
    } catch (e) {
      // Complete with error
      completer.completeError(e);
      _pendingRequests.remove(conversationId);
      rethrow;
    }
  }

  /// Get cached key if valid
  String? _getCachedKey(String conversationId) {
    final key = _keyCache[conversationId];
    final timestamp = _cacheTimestamps[conversationId];

    if (key != null && timestamp != null) {
      final age = DateTime.now().difference(timestamp);
      if (age < _cacheExpiry) {
        return key;
      } else {
        // Remove expired key
        _keyCache.remove(conversationId);
        _cacheTimestamps.remove(conversationId);
      }
    }

    return null;
  }

  /// Cache a conversation key
  void _cacheKey(String conversationId, String key) {
    // Implement LRU eviction if cache is full
    if (_keyCache.length >= _maxCacheSize) {
      _evictOldestKey();
    }

    _keyCache[conversationId] = key;
    _cacheTimestamps[conversationId] = DateTime.now();
  }

  /// Evict the oldest cached key
  void _evictOldestKey() {
    if (_cacheTimestamps.isEmpty) return;

    String? oldestKey;
    DateTime? oldestTime;

    for (final entry in _cacheTimestamps.entries) {
      if (oldestTime == null || entry.value.isBefore(oldestTime)) {
        oldestTime = entry.value;
        oldestKey = entry.key;
      }
    }

    if (oldestKey != null) {
      _keyCache.remove(oldestKey);
      _cacheTimestamps.remove(oldestKey);
      debugPrint('🗑️ Evicted oldest cached key: $oldestKey');
    }
  }

  /// Preload conversation keys for better performance
  Future<void> preloadKeys(
    List<String> conversationIds,
    Future<String> Function(String) keyRetriever,
  ) async {
    final uncachedIds =
        conversationIds.where((id) => _getCachedKey(id) == null).toList();

    if (uncachedIds.isEmpty) {
      debugPrint('⚡ All conversation keys already cached');
      return;
    }

    debugPrint('🚀 Preloading ${uncachedIds.length} conversation keys...');

    // Load keys in parallel
    final futures =
        uncachedIds.map((id) => getConversationKey(id, () => keyRetriever(id)));

    await Future.wait(futures);
    debugPrint('✅ Preloaded ${uncachedIds.length} conversation keys');
  }

  /// Invalidate a specific conversation key
  void invalidateKey(String conversationId) {
    _keyCache.remove(conversationId);
    _cacheTimestamps.remove(conversationId);
    debugPrint('🗑️ Invalidated conversation key: $conversationId');
  }

  /// Clear all cached keys
  void clearCache() {
    final count = _keyCache.length;
    _keyCache.clear();
    _cacheTimestamps.clear();
    _pendingRequests.clear();
    debugPrint('🗑️ Cleared $count cached conversation keys');
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    final now = DateTime.now();
    int validKeys = 0;
    int expiredKeys = 0;

    for (final timestamp in _cacheTimestamps.values) {
      final age = now.difference(timestamp);
      if (age < _cacheExpiry) {
        validKeys++;
      } else {
        expiredKeys++;
      }
    }

    final totalRequests = _keyCache.length + _pendingRequests.length;
    final cacheHitRate = totalRequests > 0 ? validKeys / totalRequests : 0.0;

    return {
      'totalKeys': _keyCache.length,
      'validKeys': validKeys,
      'expiredKeys': expiredKeys,
      'pendingRequests': _pendingRequests.length,
      'cacheHitRate': cacheHitRate,
    };
  }

  /// Cleanup expired keys
  void cleanup() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (final entry in _cacheTimestamps.entries) {
      final age = now.difference(entry.value);
      if (age >= _cacheExpiry) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _keyCache.remove(key);
      _cacheTimestamps.remove(key);
    }

    if (expiredKeys.isNotEmpty) {
      debugPrint(
          '🗑️ Cleaned up ${expiredKeys.length} expired conversation keys');
    }
  }
}
