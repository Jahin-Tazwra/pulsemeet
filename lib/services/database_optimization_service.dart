import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Database optimization service for efficient message queries
///
/// This service provides:
/// - Composite index management for optimal query performance
/// - Cursor-based pagination for infinite scroll
/// - Batch query optimization
/// - Real-time subscription optimization
class DatabaseOptimizationService {
  static final DatabaseOptimizationService _instance =
      DatabaseOptimizationService._internal();
  factory DatabaseOptimizationService() => _instance;
  DatabaseOptimizationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // Query optimization configuration
  static const int _defaultBatchSize = 50;
  static const int _maxBatchSize = 100;
  static const Duration _queryTimeout = Duration(seconds: 10);

  // Performance tracking
  final Map<String, List<int>> _queryPerformance = {};
  final Map<String, DateTime> _lastOptimization = {};

  /// Initialize database optimizations
  Future<void> initialize() async {
    debugPrint('🗄️ Initializing database optimizations...');

    try {
      await _createOptimalIndexes();
      await _optimizeRealTimeSubscriptions();
      debugPrint('✅ Database optimizations completed');
    } catch (e) {
      debugPrint('❌ Database optimization failed: $e');
    }
  }

  /// Create optimal indexes for message queries
  Future<void> _createOptimalIndexes() async {
    debugPrint('📊 Creating optimal database indexes...');

    try {
      // Composite index for conversation messages (conversation_id, created_at)
      await _createIndexIfNotExists(
        'idx_messages_conversation_time',
        'messages',
        ['conversation_id', 'created_at DESC'],
      );

      // Index for message status queries
      await _createIndexIfNotExists(
        'idx_messages_status',
        'messages',
        ['conversation_id', 'status', 'created_at DESC'],
      );

      // Index for sender queries
      await _createIndexIfNotExists(
        'idx_messages_sender',
        'messages',
        ['sender_id', 'created_at DESC'],
      );

      // Index for unread message queries
      await _createIndexIfNotExists(
        'idx_messages_unread',
        'messages',
        ['conversation_id', 'status', 'sender_id'],
      );

      // Conversation participants index
      await _createIndexIfNotExists(
        'idx_conversation_participants_user',
        'conversation_participants',
        ['user_id', 'last_read_at DESC'],
      );

      debugPrint('✅ Database indexes created successfully');
    } catch (e) {
      debugPrint('❌ Error creating indexes: $e');
    }
  }

  /// Create index if it doesn't exist
  Future<void> _createIndexIfNotExists(
    String indexName,
    String tableName,
    List<String> columns,
  ) async {
    try {
      final columnList = columns.join(', ');
      final sql = '''
        CREATE INDEX IF NOT EXISTS $indexName
        ON $tableName ($columnList)
      ''';

      await _supabase.rpc('execute_sql', params: {'sql': sql});
      debugPrint('📊 Created index: $indexName on $tableName');
    } catch (e) {
      debugPrint('⚠️ Index creation skipped for $indexName: $e');
    }
  }

  /// Optimize real-time subscriptions
  Future<void> _optimizeRealTimeSubscriptions() async {
    debugPrint('📡 Optimizing real-time subscriptions...');

    try {
      // Enable row-level security optimizations
      await _supabase.rpc('optimize_rls_policies');
      debugPrint('✅ RLS policies optimized');
    } catch (e) {
      debugPrint('⚠️ RLS optimization skipped: $e');
    }
  }

  /// Load messages with cursor-based pagination
  Future<MessageBatch> loadMessagesWithCursor(
    String conversationId, {
    String? cursor,
    int limit = _defaultBatchSize,
    bool ascending = false,
  }) async {
    final queryTimer = Stopwatch()..start();

    try {
      debugPrint('📥 Loading messages with cursor for: $conversationId');

      // Validate limit
      final safeLimit = limit.clamp(1, _maxBatchSize);

      // Build optimized query
      var queryBuilder = _supabase
          .from('messages')
          .select()
          .eq('conversation_id', conversationId);

      // Apply cursor-based pagination
      if (cursor != null) {
        if (ascending) {
          queryBuilder = queryBuilder.filter('created_at', 'gt', cursor);
        } else {
          queryBuilder = queryBuilder.filter('created_at', 'lt', cursor);
        }
      }

      // Apply ordering and limit
      final query = queryBuilder
          .order('created_at', ascending: ascending)
          .limit(safeLimit + 1); // +1 to check if there are more messages

      // Execute query with timeout
      final response = await query.timeout(_queryTimeout);

      queryTimer.stop();
      _trackQueryPerformance('load_messages', queryTimer.elapsedMilliseconds);

      final messagesData =
          (response as List<dynamic>).cast<Map<String, dynamic>>();

      // Check if there are more messages
      final hasMore = messagesData.length > safeLimit;
      if (hasMore) {
        messagesData.removeLast(); // Remove the extra message
      }

      // Get next cursor
      String? nextCursor;
      if (hasMore && messagesData.isNotEmpty) {
        nextCursor = messagesData.last['created_at'] as String;
      }

      debugPrint(
          '📊 Loaded ${messagesData.length} messages in ${queryTimer.elapsedMilliseconds}ms');

      return MessageBatch(
        messages: messagesData,
        nextCursor: nextCursor,
        hasMore: hasMore,
        loadTimeMs: queryTimer.elapsedMilliseconds,
      );
    } catch (e) {
      queryTimer.stop();
      debugPrint('❌ Error loading messages with cursor: $e');
      throw DatabaseException('Failed to load messages: $e');
    }
  }

  /// Batch load multiple conversations efficiently
  Future<Map<String, List<Map<String, dynamic>>>> batchLoadConversationMessages(
    List<String> conversationIds, {
    int limitPerConversation = 20,
  }) async {
    final batchTimer = Stopwatch()..start();

    try {
      debugPrint(
          '📦 Batch loading messages for ${conversationIds.length} conversations');

      // Use efficient batch query
      final response =
          await _supabase.rpc('batch_load_conversation_messages', params: {
        'conversation_ids': conversationIds,
        'limit_per_conversation': limitPerConversation,
      }).timeout(_queryTimeout);

      batchTimer.stop();
      _trackQueryPerformance('batch_load', batchTimer.elapsedMilliseconds);

      // Group messages by conversation
      final result = <String, List<Map<String, dynamic>>>{};
      for (final conversationId in conversationIds) {
        result[conversationId] = [];
      }

      if (response is List) {
        for (final message in response) {
          final conversationId = message['conversation_id'] as String;
          if (result.containsKey(conversationId)) {
            result[conversationId]!.add(message as Map<String, dynamic>);
          }
        }
      }

      debugPrint(
          '📊 Batch loaded messages in ${batchTimer.elapsedMilliseconds}ms');
      return result;
    } catch (e) {
      batchTimer.stop();
      debugPrint('❌ Error in batch loading: $e');
      throw DatabaseException('Failed to batch load messages: $e');
    }
  }

  /// Get unread message count efficiently
  Future<Map<String, int>> getUnreadCounts(List<String> conversationIds) async {
    final countTimer = Stopwatch()..start();

    try {
      debugPrint(
          '📊 Getting unread counts for ${conversationIds.length} conversations');

      final response = await _supabase.rpc('get_unread_counts', params: {
        'conversation_ids': conversationIds,
      }).timeout(_queryTimeout);

      countTimer.stop();
      _trackQueryPerformance('unread_counts', countTimer.elapsedMilliseconds);

      final result = <String, int>{};
      if (response is List) {
        for (final item in response) {
          result[item['conversation_id'] as String] =
              item['unread_count'] as int;
        }
      }

      debugPrint(
          '📊 Unread counts retrieved in ${countTimer.elapsedMilliseconds}ms');
      return result;
    } catch (e) {
      countTimer.stop();
      debugPrint('❌ Error getting unread counts: $e');
      return {};
    }
  }

  /// Optimize query for specific conversation
  Future<void> optimizeConversationQueries(String conversationId) async {
    try {
      // Analyze query patterns and optimize
      await _supabase.rpc('analyze_conversation_queries', params: {
        'conversation_id': conversationId,
      });

      _lastOptimization[conversationId] = DateTime.now();
      debugPrint('🔧 Optimized queries for conversation: $conversationId');
    } catch (e) {
      debugPrint('⚠️ Query optimization skipped for $conversationId: $e');
    }
  }

  /// Track query performance for monitoring
  void _trackQueryPerformance(String queryType, int durationMs) {
    if (!_queryPerformance.containsKey(queryType)) {
      _queryPerformance[queryType] = [];
    }

    _queryPerformance[queryType]!.add(durationMs);

    // Keep only last 100 measurements
    if (_queryPerformance[queryType]!.length > 100) {
      _queryPerformance[queryType]!.removeAt(0);
    }
  }

  /// Get performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    final metrics = <String, dynamic>{};

    for (final entry in _queryPerformance.entries) {
      final durations = entry.value;
      if (durations.isNotEmpty) {
        final average = durations.reduce((a, b) => a + b) / durations.length;
        final min = durations.reduce((a, b) => a < b ? a : b);
        final max = durations.reduce((a, b) => a > b ? a : b);

        metrics[entry.key] = {
          'average_ms': average.round(),
          'min_ms': min,
          'max_ms': max,
          'sample_count': durations.length,
        };
      }
    }

    return metrics;
  }

  /// Check if conversation needs query optimization
  bool shouldOptimizeConversation(String conversationId) {
    final lastOpt = _lastOptimization[conversationId];
    if (lastOpt == null) return true;

    return DateTime.now().difference(lastOpt) > const Duration(hours: 24);
  }
}

/// Message batch result for cursor-based pagination
class MessageBatch {
  final List<Map<String, dynamic>> messages;
  final String? nextCursor;
  final bool hasMore;
  final int loadTimeMs;

  MessageBatch({
    required this.messages,
    this.nextCursor,
    required this.hasMore,
    required this.loadTimeMs,
  });
}

/// Database exception
class DatabaseException implements Exception {
  final String message;
  DatabaseException(this.message);

  @override
  String toString() => 'DatabaseException: $message';
}
