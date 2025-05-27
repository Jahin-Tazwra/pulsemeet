import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message.dart';
// import 'network_resilience_service.dart';

/// High-performance message status service for instant status updates (<50ms)
///
/// This service provides:
/// - Instant optimistic UI status updates (<50ms)
/// - Background server synchronization
/// - Conflict resolution and rollback mechanisms
/// - Comprehensive retry logic for network failures
class MessageStatusService {
  static final MessageStatusService _instance =
      MessageStatusService._internal();
  factory MessageStatusService() => _instance;
  static MessageStatusService get instance => _instance;
  MessageStatusService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  // final NetworkResilienceService _networkService =
  //     NetworkResilienceService.instance;

  // Status tracking
  final Map<String, MessageStatus> _optimisticStatuses = {};
  final Map<String, MessageStatus> _serverStatuses = {};
  final Map<String, DateTime> _statusTimestamps = {};
  final Map<String, int> _retryAttempts = {};

  // Performance tracking
  final Map<String, Stopwatch> _statusTimers = {};
  final StreamController<MessageStatusUpdate> _statusController =
      StreamController.broadcast();

  // Configuration
  static const Duration _statusTimeout = Duration(seconds: 30);
  static const int _maxRetryAttempts = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  /// Stream of message status updates
  Stream<MessageStatusUpdate> get statusUpdates => _statusController.stream;

  /// Update message status with instant UI feedback (<50ms target)
  Future<void> updateMessageStatus(
    String messageId,
    MessageStatus newStatus, {
    bool optimistic = true,
  }) async {
    final timer = Stopwatch()..start();
    _statusTimers[messageId] = timer;

    debugPrint('📊 Updating status for message $messageId: $newStatus');
    debugPrint(
        '🔧 MessageStatusService: updateMessageStatus called with optimistic=$optimistic');

    try {
      if (optimistic) {
        debugPrint('🔧 MessageStatusService: Taking optimistic path');
        // Phase 1: Instant optimistic UI update (<50ms)
        _updateOptimisticStatus(messageId, newStatus);
        timer.stop();
        debugPrint(
            '⚡ Optimistic status update completed in ${timer.elapsedMilliseconds}ms');

        // Phase 2: Background server sync
        _syncStatusToServer(messageId, newStatus);
      } else {
        debugPrint('🔧 MessageStatusService: Taking direct server update path');
        // Direct server update (for critical status changes)
        await _updateServerStatus(messageId, newStatus);

        // CRITICAL FIX: Always emit status update for UI, even for direct server updates
        final statusUpdate = MessageStatusUpdate(
          messageId: messageId,
          status: newStatus,
          isOptimistic: false,
          isConfirmed: true,
          timestamp: DateTime.now(),
        );

        debugPrint(
            '📡 MessageStatusService: Emitting direct status update for $messageId: $newStatus');
        _statusController.add(statusUpdate);

        timer.stop();
        debugPrint(
            '📡 Server status update completed in ${timer.elapsedMilliseconds}ms');
      }
    } catch (e) {
      timer.stop();
      debugPrint('❌ Error updating message status: $e');
      _handleStatusUpdateError(messageId, newStatus, e);
    }
  }

  /// Update optimistic status instantly for UI responsiveness
  void _updateOptimisticStatus(String messageId, MessageStatus newStatus) {
    final updateTimer = Stopwatch()..start();

    // Store optimistic status
    _optimisticStatuses[messageId] = newStatus;
    _statusTimestamps[messageId] = DateTime.now();

    // Emit status update for UI
    final statusUpdate = MessageStatusUpdate(
      messageId: messageId,
      status: newStatus,
      isOptimistic: true,
      timestamp: DateTime.now(),
    );

    debugPrint(
        '📡 MessageStatusService: Emitting optimistic status update for $messageId: $newStatus');
    _statusController.add(statusUpdate);

    updateTimer.stop();
    debugPrint('⚡ Optimistic UI update: ${updateTimer.elapsedMilliseconds}ms');
  }

  /// Sync status to server in background
  void _syncStatusToServer(String messageId, MessageStatus newStatus) {
    Future.microtask(() async {
      try {
        await _updateServerStatus(messageId, newStatus);
        _confirmOptimisticStatus(messageId, newStatus);
      } catch (e) {
        debugPrint('❌ Background status sync failed: $e');
        _scheduleStatusRetry(messageId, newStatus);
      }
    });
  }

  /// Update status on server with network resilience
  Future<void> _updateServerStatus(
      String messageId, MessageStatus newStatus) async {
    final serverTimer = Stopwatch()..start();

    try {
      await _supabase.from('messages').update({
        'status': newStatus.toString().split('.').last,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', messageId);

      serverTimer.stop();
      debugPrint(
          '📡 Server status update completed in ${serverTimer.elapsedMilliseconds}ms');

      // Store confirmed server status
      _serverStatuses[messageId] = newStatus;
    } catch (e) {
      serverTimer.stop();
      debugPrint(
          '❌ Server status update failed in ${serverTimer.elapsedMilliseconds}ms: $e');
      throw e;
    }
  }

  /// Confirm optimistic status with server response
  void _confirmOptimisticStatus(
      String messageId, MessageStatus confirmedStatus) {
    final optimisticStatus = _optimisticStatuses[messageId];

    if (optimisticStatus == confirmedStatus) {
      // Optimistic update was correct
      final confirmedUpdate = MessageStatusUpdate(
        messageId: messageId,
        status: confirmedStatus,
        isOptimistic: false,
        isConfirmed: true,
        timestamp: DateTime.now(),
      );

      debugPrint(
          '📡 MessageStatusService: Emitting confirmed status update for $messageId: $confirmedStatus');
      _statusController.add(confirmedUpdate);

      debugPrint('✅ Optimistic status confirmed for message $messageId');
    } else {
      // Conflict detected - rollback optimistic update
      _rollbackOptimisticStatus(messageId, confirmedStatus);
    }

    // Cleanup
    _optimisticStatuses.remove(messageId);
    _retryAttempts.remove(messageId);
  }

  /// Rollback optimistic status due to server conflict
  void _rollbackOptimisticStatus(String messageId, MessageStatus serverStatus) {
    debugPrint('🔄 Rolling back optimistic status for message $messageId');

    final rollbackUpdate = MessageStatusUpdate(
      messageId: messageId,
      status: serverStatus,
      isOptimistic: false,
      isRollback: true,
      timestamp: DateTime.now(),
    );

    debugPrint(
        '📡 MessageStatusService: Emitting rollback status update for $messageId: $serverStatus');
    _statusController.add(rollbackUpdate);

    debugPrint('⚠️ Status rollback completed for message $messageId');
  }

  /// Schedule retry for failed status update
  void _scheduleStatusRetry(String messageId, MessageStatus targetStatus) {
    final currentAttempts = _retryAttempts[messageId] ?? 0;

    if (currentAttempts >= _maxRetryAttempts) {
      debugPrint('❌ Max retry attempts reached for message $messageId');
      _handleStatusUpdateFailure(messageId, targetStatus);
      return;
    }

    _retryAttempts[messageId] = currentAttempts + 1;

    Timer(_retryDelay * (currentAttempts + 1), () {
      debugPrint(
          '🔄 Retrying status update for message $messageId (attempt ${currentAttempts + 1})');
      _syncStatusToServer(messageId, targetStatus);
    });
  }

  /// Handle status update error
  void _handleStatusUpdateError(
      String messageId, MessageStatus targetStatus, dynamic error) {
    debugPrint('❌ Status update error for message $messageId: $error');

    // Emit error status update
    _statusController.add(MessageStatusUpdate(
      messageId: messageId,
      status: MessageStatus.failed,
      isOptimistic: false,
      hasError: true,
      error: error.toString(),
      timestamp: DateTime.now(),
    ));
  }

  /// Handle permanent status update failure
  void _handleStatusUpdateFailure(
      String messageId, MessageStatus targetStatus) {
    debugPrint('❌ Permanent status update failure for message $messageId');

    // Mark as failed and remove from optimistic tracking
    _optimisticStatuses.remove(messageId);
    _retryAttempts.remove(messageId);

    _statusController.add(MessageStatusUpdate(
      messageId: messageId,
      status: MessageStatus.failed,
      isOptimistic: false,
      isPermanentFailure: true,
      timestamp: DateTime.now(),
    ));
  }

  /// Batch update multiple message statuses for efficiency
  Future<void> batchUpdateStatuses(
      Map<String, MessageStatus> statusUpdates) async {
    final batchTimer = Stopwatch()..start();

    try {
      // Phase 1: Instant optimistic updates for all messages
      for (final entry in statusUpdates.entries) {
        _updateOptimisticStatus(entry.key, entry.value);
      }

      batchTimer.stop();
      debugPrint(
          '⚡ Batch optimistic updates completed in ${batchTimer.elapsedMilliseconds}ms');

      // Phase 2: Background server sync
      _batchSyncToServer(statusUpdates);
    } catch (e) {
      batchTimer.stop();
      debugPrint('❌ Error in batch status update: $e');
    }
  }

  /// Sync batch status updates to server
  void _batchSyncToServer(Map<String, MessageStatus> statusUpdates) {
    Future.microtask(() async {
      try {
        final updates = statusUpdates.entries
            .map((entry) => {
                  'id': entry.key,
                  'status': entry.value.toString().split('.').last,
                  'updated_at': DateTime.now().toIso8601String(),
                })
            .toList();

        await _supabase.from('messages').upsert(updates);

        // Confirm all optimistic updates
        for (final entry in statusUpdates.entries) {
          _confirmOptimisticStatus(entry.key, entry.value);
        }

        debugPrint(
            '✅ Batch server sync completed for ${statusUpdates.length} messages');
      } catch (e) {
        debugPrint('❌ Batch server sync failed: $e');
        // Schedule individual retries
        for (final entry in statusUpdates.entries) {
          _scheduleStatusRetry(entry.key, entry.value);
        }
      }
    });
  }

  /// Get current status for a message (optimistic or server)
  MessageStatus? getMessageStatus(String messageId) {
    return _optimisticStatuses[messageId] ?? _serverStatuses[messageId];
  }

  /// Check if message has pending optimistic status
  bool hasPendingStatus(String messageId) {
    return _optimisticStatuses.containsKey(messageId);
  }

  /// Get performance metrics for monitoring
  Map<String, dynamic> getPerformanceMetrics() {
    final totalUpdates = _statusTimers.length;
    final averageTime = totalUpdates > 0
        ? _statusTimers.values
                .map((t) => t.elapsedMilliseconds)
                .reduce((a, b) => a + b) /
            totalUpdates
        : 0.0;

    return {
      'total_status_updates': totalUpdates,
      'average_update_time_ms': averageTime,
      'pending_optimistic_updates': _optimisticStatuses.length,
      'failed_updates': _retryAttempts.length,
    };
  }

  /// Dispose service and cleanup resources
  void dispose() {
    _statusController.close();
    _optimisticStatuses.clear();
    _serverStatuses.clear();
    _statusTimestamps.clear();
    _retryAttempts.clear();
    _statusTimers.clear();
  }
}

/// Message status update event
class MessageStatusUpdate {
  final String messageId;
  final MessageStatus status;
  final bool isOptimistic;
  final bool isConfirmed;
  final bool isRollback;
  final bool hasError;
  final bool isPermanentFailure;
  final String? error;
  final DateTime timestamp;

  MessageStatusUpdate({
    required this.messageId,
    required this.status,
    this.isOptimistic = false,
    this.isConfirmed = false,
    this.isRollback = false,
    this.hasError = false,
    this.isPermanentFailure = false,
    this.error,
    required this.timestamp,
  });
}
