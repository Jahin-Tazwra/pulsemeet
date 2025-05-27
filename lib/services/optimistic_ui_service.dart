import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message.dart';
import 'message_status_service.dart';

/// Service for instant optimistic UI updates to eliminate perceived lag
class OptimisticUIService {
  static OptimisticUIService? _instance;
  static OptimisticUIService get instance =>
      _instance ??= OptimisticUIService._();

  OptimisticUIService._() {
    debugPrint('🔧 OptimisticUIService: Constructor called');
    debugPrint(
        '🔧 OptimisticUIService: MessageStatusService instance: $_messageStatusService');
    _initializeStatusSubscription();
  }

  // Supabase instance for getting current user
  final SupabaseClient _supabase = Supabase.instance.client;

  // Message status service for listening to status updates (singleton instance)
  final MessageStatusService _messageStatusService =
      MessageStatusService.instance;
  StreamSubscription<MessageStatusUpdate>? _statusSubscription;

  // Optimistic message streams
  final Map<String, StreamController<List<Message>>> _optimisticMessageStreams =
      {};
  final Map<String, List<Message>> _optimisticMessages = {};
  final Map<String, Set<String>> _pendingMessages = {};
  final Map<String, Set<String>> _failedMessages = {};

  /// Get optimistic message stream for a conversation
  Stream<List<Message>> getOptimisticMessageStream(String conversationId) {
    if (!_optimisticMessageStreams.containsKey(conversationId)) {
      _optimisticMessageStreams[conversationId] =
          StreamController<List<Message>>.broadcast();
      // CRITICAL FIX: Don't initialize with empty list - wait for initializeWithMessages
      _pendingMessages[conversationId] = {};
      _failedMessages[conversationId] = {};

      debugPrint(
          '🔄 Created new optimistic stream for conversation: $conversationId (no initial state)');
    }
    return _optimisticMessageStreams[conversationId]!.stream;
  }

  /// Initialize optimistic UI with existing messages (prevents empty state flash)
  void initializeWithMessages(
      String conversationId, List<Message> initialMessages) {
    // Ensure stream exists
    if (!_optimisticMessageStreams.containsKey(conversationId)) {
      _optimisticMessageStreams[conversationId] =
          StreamController<List<Message>>.broadcast();
      _pendingMessages[conversationId] = {};
      _failedMessages[conversationId] = {};
    }

    // CRITICAL FIX: Check if we already have cached messages for this conversation
    final existingMessages = _optimisticMessages[conversationId];

    if (existingMessages != null && existingMessages.isNotEmpty) {
      debugPrint(
          '🔍 NAVIGATION DEBUG: Found ${existingMessages.length} existing cached messages - preserving them');
      debugPrint(
          '🔍 NAVIGATION DEBUG: Ignoring ${initialMessages.length} initialMessages to preserve cache');

      // Emit the existing cached messages immediately to restore UI state
      _optimisticMessageStreams[conversationId]
          ?.add(List.from(existingMessages));

      debugPrint(
          '🚀 Restored ${existingMessages.length} cached messages from OptimisticUI cache');
      return; // Exit early to preserve cached messages
    }

    // CRITICAL DEBUG: Log message order before and after sorting
    debugPrint(
        '🔍 NAVIGATION DEBUG: No cached messages found - initializing with ${initialMessages.length} messages');
    if (initialMessages.isNotEmpty) {
      debugPrint(
          '🔍 NAVIGATION DEBUG: First message timestamp: ${initialMessages.first.createdAt}');
      debugPrint(
          '🔍 NAVIGATION DEBUG: Last message timestamp: ${initialMessages.last.createdAt}');
      debugPrint(
          '🔍 NAVIGATION DEBUG: Messages already sorted: ${_isAlreadySorted(initialMessages)}');
    }

    // CRITICAL FIX: Consistent chronological sorting (oldest first)
    // This ensures messages always appear in the same order regardless of source
    // Oldest messages (index 0) at top, newest messages at bottom (WhatsApp-like)
    final sortedMessages = [...initialMessages];
    sortedMessages.sort((a, b) {
      final timeComparison = a.createdAt.compareTo(b.createdAt);
      // If timestamps are identical, use ID for stable sorting
      if (timeComparison == 0) {
        return a.id.compareTo(b.id);
      }
      return timeComparison;
    });

    _optimisticMessages[conversationId] = sortedMessages;

    // CRITICAL FIX: Always emit the messages, even if empty
    // This ensures the stream subscription gets the initial state
    _optimisticMessageStreams[conversationId]?.add(List.from(sortedMessages));

    debugPrint(
        '🚀 Initialized optimistic UI with ${initialMessages.length} messages (chronological order)');

    if (sortedMessages.isNotEmpty) {
      debugPrint(
          '🔍 NAVIGATION DEBUG: After sorting - First: ${sortedMessages.first.createdAt}');
      debugPrint(
          '🔍 NAVIGATION DEBUG: After sorting - Last: ${sortedMessages.last.createdAt}');
    }
  }

  /// Helper method to check if messages are already sorted
  bool _isAlreadySorted(List<Message> messages) {
    for (int i = 1; i < messages.length; i++) {
      if (messages[i].createdAt.isBefore(messages[i - 1].createdAt)) {
        return false;
      }
    }
    return true;
  }

  /// Add optimistic message instantly (0ms perceived delay)
  void addOptimisticMessage(String conversationId, Message message,
      {Function(String, Message)? onLastMessageUpdate}) {
    debugPrint('🚨🚨🚨 NEW CODE IS RUNNING - OPTIMISTIC MESSAGE ADD 🚨🚨🚨');

    // Ensure conversation is initialized
    if (!_optimisticMessages.containsKey(conversationId)) {
      _optimisticMessages[conversationId] = [];
    }

    final messages = _optimisticMessages[conversationId]!;
    final pending = _pendingMessages[conversationId] ?? {};

    debugPrint(
        '🔍 FIXED CODE: Adding optimistic message with timestamp: ${message.createdAt}');
    debugPrint('🔍 FIXED CODE: Current message count: ${messages.length}');

    if (messages.isNotEmpty) {
      final lastMessage = messages.last;
      debugPrint(
          '🔍 FIXED CODE: Last existing message timestamp: ${lastMessage.createdAt}');
      debugPrint(
          '🔍 FIXED CODE: New message is ${message.createdAt.isAfter(lastMessage.createdAt) ? 'NEWER' : 'OLDER'} than last message');
    }

    // CRITICAL FIX: New messages should ALWAYS go at the END (bottom)
    // Don't sort - just append to maintain chronological order
    messages.add(message);
    pending.add(message.id);

    // Emit instantly to UI
    _optimisticMessageStreams[conversationId]?.add(List.from(messages));

    // CRITICAL FIX: Update conversation service's last message cache
    if (onLastMessageUpdate != null) {
      onLastMessageUpdate(conversationId, message);
    }

    final insertIndex = messages.length - 1; // Always at the end
    debugPrint(
        '🚨 FIXED CODE: Added optimistic message at position $insertIndex (should be at END): ${message.id}');
  }

  /// Update message status when server confirms
  void confirmMessage(
      String conversationId, String messageId, Message confirmedMessage) {
    final messages = _optimisticMessages[conversationId];
    final pending = _pendingMessages[conversationId];

    if (messages != null && pending != null) {
      // Find and update the optimistic message
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        // Ensure the confirmed message has the correct status
        final updatedMessage = confirmedMessage.copyWith(
          status: MessageStatus.sent,
        );
        messages[index] = updatedMessage;
        pending.remove(messageId);

        // Re-sort messages to maintain order
        messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        // Emit updated list
        _optimisticMessageStreams[conversationId]?.add(List.from(messages));

        debugPrint(
            '✅ Confirmed optimistic message: $messageId with status: ${updatedMessage.status}');
      }
    }
  }

  /// Mark message as failed
  void markMessageFailed(
      String conversationId, String messageId, String error) {
    final messages = _optimisticMessages[conversationId];
    final pending = _pendingMessages[conversationId];
    final failed = _failedMessages[conversationId];

    if (messages != null && pending != null && failed != null) {
      // Update message status to failed
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final failedMessage = messages[index].copyWith(
          status: MessageStatus.failed,
          isOffline: true,
        );
        messages[index] = failedMessage;

        pending.remove(messageId);
        failed.add(messageId);

        // Emit updated list
        _optimisticMessageStreams[conversationId]?.add(List.from(messages));

        debugPrint('❌ Marked message as failed: $messageId - $error');
      }
    }
  }

  /// Merge server messages with optimistic messages (intelligent merge to prevent disappearing)
  void mergeServerMessages(
      String conversationId, List<Message> serverMessages) {
    final optimisticMessages = _optimisticMessages[conversationId] ?? [];
    final pending = _pendingMessages[conversationId] ?? {};

    debugPrint('🔄 🚨 MERGE DEBUG: ===== STARTING MERGE OPERATION =====');
    debugPrint('🔄 🚨 MERGE DEBUG: Conversation: $conversationId');
    debugPrint(
        '🔄 🚨 MERGE DEBUG: Optimistic messages: ${optimisticMessages.length}');
    debugPrint('🔄 🚨 MERGE DEBUG: Server messages: ${serverMessages.length}');
    debugPrint('🔄 🚨 MERGE DEBUG: Pending messages: ${pending.length}');

    // CROSS-USER REAL-TIME FIX: Check for new messages from other users first
    final optimisticIds = optimisticMessages.map((m) => m.id).toSet();
    final serverIds = serverMessages.map((m) => m.id).toSet();
    final newMessageIds = serverIds.difference(optimisticIds);

    if (newMessageIds.isNotEmpty) {
      debugPrint(
          '🚀 REAL-TIME MERGE: Detected ${newMessageIds.length} NEW messages from other users');
      debugPrint(
          '🚀 REAL-TIME MERGE: New message IDs: ${newMessageIds.take(3).join(', ')}${newMessageIds.length > 3 ? '...' : ''}');

      // Fast-track new messages for instant UI delivery
      final newMessages =
          serverMessages.where((m) => newMessageIds.contains(m.id)).toList();
      final mergedMessages = [...optimisticMessages, ...newMessages];
      mergedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      // Update cache and emit immediately
      _optimisticMessages[conversationId] = mergedMessages;
      _optimisticMessageStreams[conversationId]?.add(List.from(mergedMessages));

      debugPrint(
          '⚡ REAL-TIME MERGE: Instantly delivered ${newMessages.length} new messages to UI');

      // Continue with full merge for any remaining updates
      if (newMessageIds.length < serverMessages.length) {
        debugPrint(
            '🔄 REAL-TIME MERGE: Continuing with full merge for remaining updates');
      } else {
        // All messages were new, no need for further processing
        return;
      }
    }

    if (optimisticMessages.isNotEmpty) {
      debugPrint(
          '🔄 MERGE DEBUG: First optimistic: ${optimisticMessages.first.id} at ${optimisticMessages.first.createdAt}');
      debugPrint(
          '🔄 MERGE DEBUG: Last optimistic: ${optimisticMessages.last.id} at ${optimisticMessages.last.createdAt}');
    }

    if (serverMessages.isNotEmpty) {
      debugPrint(
          '🔄 MERGE DEBUG: First server: ${serverMessages.first.id} at ${serverMessages.first.createdAt}');
      debugPrint(
          '🔄 MERGE DEBUG: Last server: ${serverMessages.last.id} at ${serverMessages.last.createdAt}');
    }

    // CRITICAL FIX: If no server messages, still emit to stream to complete initial load
    if (serverMessages.isEmpty) {
      debugPrint('🔄 No server messages to merge, keeping current state');

      // CRITICAL FIX: For empty conversations, we still need to emit to the stream
      // This ensures ChatScreen receives the update and sets _isInitialLoadComplete = true
      if (optimisticMessages.isEmpty) {
        debugPrint(
            '🔄 Empty conversation detected - emitting empty list to complete initial load');
        _optimisticMessageStreams[conversationId]?.add(<Message>[]);
      }
      return;
    }

    // CRITICAL FIX: Prevent cache truncation during background updates
    // If we have more cached messages than server messages, it's likely a partial fetch
    if (optimisticMessages.length > serverMessages.length) {
      debugPrint(
          '🔄 MERGE DEBUG: ⚠️ CACHE TRUNCATION PREVENTION: Cached (${optimisticMessages.length}) > Server (${serverMessages.length})');
      debugPrint(
          '🔄 MERGE DEBUG: This appears to be a partial server fetch - using additive merge to prevent message loss');

      // Use additive merge instead of replacement to prevent cache truncation
      _performAdditiveMerge(
          conversationId, optimisticMessages, serverMessages, pending);
      return;
    }

    // CRITICAL FIX: If we have cached messages, prioritize preserving read status
    // This prevents navigation from reverting read messages back to sent
    if (optimisticMessages.isNotEmpty) {
      debugPrint(
          '🔄 MERGE DEBUG: Prioritizing read status preservation during navigation merge');
    }

    // CRITICAL FIX: Enhanced content-based merge detection to prevent positioning issues
    // Special case: If we have different message counts, it's likely a subset vs full set
    // In this case, we should merge but be very careful about order detection
    final isSubsetExpansion = optimisticMessages.length < serverMessages.length;
    final isExactMatch = optimisticMessages.length == serverMessages.length;

    // CRITICAL FIX: For subset expansion during navigation, use optimized merge
    if (isSubsetExpansion &&
        optimisticMessages.isNotEmpty &&
        serverMessages.isNotEmpty) {
      debugPrint(
          '🔄 MERGE DEBUG: Detected subset expansion - using fast merge path');

      // Check if optimistic messages are a subset of server messages
      final optimisticIds = optimisticMessages.map((m) => m.id).toSet();
      final serverIds = serverMessages.map((m) => m.id).toSet();

      if (optimisticIds.difference(serverIds).isEmpty) {
        debugPrint(
            '🔄 MERGE DEBUG: Confirmed subset - merging with status preservation');

        // CRITICAL FIX: Preserve read status during subset expansion
        // Create a map of optimistic messages for status lookup
        final optimisticStatusMap = <String, MessageStatus>{};
        for (final msg in optimisticMessages) {
          optimisticStatusMap[msg.id] = msg.status;
        }

        // Merge server messages while preserving read status
        final mergedMessages = serverMessages.map((serverMessage) {
          final optimisticStatus = optimisticStatusMap[serverMessage.id];
          if (optimisticStatus != null) {
            final preservedStatus =
                _getBetterStatus(optimisticStatus, serverMessage.status);
            if (preservedStatus != serverMessage.status) {
              debugPrint(
                  '🎯 SUBSET MERGE: Preserving status for ${serverMessage.id}: ${serverMessage.status} → $preservedStatus');
              return serverMessage.copyWith(status: preservedStatus);
            }
          }
          return serverMessage;
        }).toList();

        _optimisticMessages[conversationId] = mergedMessages;
        _optimisticMessageStreams[conversationId]
            ?.add(List.from(mergedMessages));

        debugPrint(
            '🔄 MERGE DEBUG: Status-preserving subset merge completed: ${mergedMessages.length} messages');
        return;
      }
    }

    if (isExactMatch && optimisticMessages.isNotEmpty) {
      final existingMap = <String, Message>{};
      for (final msg in optimisticMessages) {
        existingMap[msg.id] = msg;
      }

      bool hasContentChanges = false;
      bool hasNewMessages = false;
      bool hasOrderChanges = false;

      // Check for new messages first
      for (final serverMessage in serverMessages) {
        if (!existingMap.containsKey(serverMessage.id)) {
          hasNewMessages = true;
          debugPrint('🔄 New message detected: ${serverMessage.id}');
          break;
        }
      }

      // Check for content changes and order changes
      if (!hasNewMessages) {
        for (int i = 0; i < serverMessages.length; i++) {
          final serverMessage = serverMessages[i];
          final existingMessage = existingMap[serverMessage.id];

          if (existingMessage == null) continue;

          // Check for content changes
          if (existingMessage.content != serverMessage.content ||
              existingMessage.messageType != serverMessage.messageType ||
              existingMessage.isDeleted != serverMessage.isDeleted ||
              existingMessage.isEdited != serverMessage.isEdited) {
            hasContentChanges = true;
            debugPrint('🔄 Content change detected: ${serverMessage.id}');
            break;
          }

          // CRITICAL FIX: Much more conservative order change detection
          // Only flag as order change if there's a real chronological inconsistency
          // Skip order checking for subset expansions to prevent false positives
          if (i < optimisticMessages.length && !isSubsetExpansion) {
            final optimisticMessage = optimisticMessages[i];
            if (optimisticMessage.id != serverMessage.id) {
              // Only check for order changes if both messages exist in both lists
              final optimisticIndex = optimisticMessages
                  .indexWhere((m) => m.id == serverMessage.id);
              final serverIndex = serverMessages
                  .indexWhere((m) => m.id == optimisticMessage.id);

              if (optimisticIndex != -1 && serverIndex != -1) {
                // Both messages exist in both lists - check chronological consistency
                final serverTime = serverMessage.createdAt;
                final optimisticTime = optimisticMessage.createdAt;

                // Only flag as order change if timestamps are actually out of order
                if ((serverTime.isBefore(optimisticTime) &&
                        i > optimisticIndex) ||
                    (serverTime.isAfter(optimisticTime) &&
                        i < optimisticIndex)) {
                  hasOrderChanges = true;
                  debugPrint(
                      '🔄 Real chronological order change detected: ${serverMessage.id} vs ${optimisticMessage.id}');
                  break;
                } else {
                  debugPrint(
                      '🔄 Position difference but chronological order is correct (subset expansion)');
                }
              }
            }
          }

          // Status and timestamp changes are metadata - log but don't trigger repositioning
          if (existingMessage.status != serverMessage.status ||
              existingMessage.updatedAt != serverMessage.updatedAt) {
            debugPrint(
                '🔄 Metadata change detected: ${serverMessage.id} (status/timestamp only)');
          }
        }
      }

      if (!hasNewMessages && !hasContentChanges && !hasOrderChanges) {
        debugPrint(
            '🔄 SKIPPING REDUNDANT MERGE - only metadata changes detected (PREVENTS POSITIONING ISSUES)');

        // Update metadata silently without triggering UI repositioning
        final updatedMessages = <Message>[...optimisticMessages];
        bool hasStatusChanges = false;

        for (int i = 0; i < updatedMessages.length; i++) {
          final existingMessage = updatedMessages[i];
          final serverMessage = serverMessages.firstWhere(
            (m) => m.id == existingMessage.id,
            orElse: () => existingMessage,
          );

          // Update only metadata fields with status preservation
          final preservedStatus =
              _getBetterStatus(existingMessage.status, serverMessage.status);

          if (existingMessage.status != preservedStatus ||
              existingMessage.updatedAt != serverMessage.updatedAt) {
            updatedMessages[i] = existingMessage.copyWith(
              status: preservedStatus,
              updatedAt: serverMessage.updatedAt,
            );

            // Track if there are status changes that affect UI
            if (existingMessage.status != preservedStatus) {
              hasStatusChanges = true;
              debugPrint(
                  '🔄 Status change detected: ${serverMessage.id} ${existingMessage.status} → $preservedStatus');
            }
          }
        }

        // Update cache
        _optimisticMessages[conversationId] = updatedMessages;

        // CRITICAL FIX: Emit stream update for status changes to update UI indicators
        if (hasStatusChanges) {
          _optimisticMessageStreams[conversationId]
              ?.add(List.from(updatedMessages));
          debugPrint(
              '🔄 Updated metadata with stream emission for status changes');
        } else {
          debugPrint('🔄 Updated metadata silently without UI repositioning');
        }
        return;
      } else {
        debugPrint(
            '🔄 Proceeding with merge - found content/structural changes in ${serverMessages.length} messages');
      }
    } else {
      debugPrint(
          '🔄 Message count changed: ${optimisticMessages.length} -> ${serverMessages.length}');

      // Note: Subset expansion is now handled earlier in the method
    }

    // Create a map of existing messages by ID for fast lookup
    final existingMessageMap = <String, Message>{};
    for (final message in optimisticMessages) {
      existingMessageMap[message.id] = message;
    }

    // Start with existing messages to prevent disappearing
    final updatedMessages = <Message>[...optimisticMessages];
    final confirmedIds = <String>{};
    var hasChanges = false;

    // Update existing messages with server data and add new ones
    for (final serverMessage in serverMessages) {
      final existingIndex =
          updatedMessages.indexWhere((m) => m.id == serverMessage.id);

      if (existingIndex != -1) {
        // Check if the message actually changed before updating
        final existingMessage = updatedMessages[existingIndex];
        final preservedStatus =
            _getBetterStatus(existingMessage.status, serverMessage.status);

        // Only update if status or content changed
        if (existingMessage.status != preservedStatus ||
            existingMessage.content != serverMessage.content) {
          final updatedMessage =
              serverMessage.copyWith(status: preservedStatus);
          updatedMessages[existingIndex] = updatedMessage;
          confirmedIds.add(serverMessage.id);
          hasChanges = true;
        }
      } else {
        // New server message - add it in correct chronological position
        updatedMessages.add(serverMessage);
        hasChanges = true;
      }
    }

    // Remove confirmed messages from pending
    for (final id in confirmedIds) {
      pending.remove(id);
    }

    // Only sort and emit if there were actual changes
    if (hasChanges) {
      // CRITICAL FIX: Ensure stable sorting to prevent position changes
      updatedMessages.sort((a, b) {
        final timeComparison = a.createdAt.compareTo(b.createdAt);
        // If timestamps are identical, use ID for stable sorting
        if (timeComparison == 0) {
          return a.id.compareTo(b.id);
        }
        return timeComparison;
      });

      // Update cache and emit
      _optimisticMessages[conversationId] = updatedMessages;
      _optimisticMessageStreams[conversationId]
          ?.add(List.from(updatedMessages));

      debugPrint('🔄 🚨 MERGE DEBUG: ===== MERGE COMPLETED =====');
      debugPrint(
          '🔄 🚨 MERGE DEBUG: Final message count: ${updatedMessages.length}');
      debugPrint(
          '🔄 🚨 MERGE DEBUG: Merged ${serverMessages.length} server messages with ${pending.length} pending optimistic messages');

      if (updatedMessages.isNotEmpty) {
        debugPrint(
            '🔄 🚨 MERGE DEBUG: Final range - First: ${updatedMessages.first.createdAt} (${updatedMessages.first.id})');
        debugPrint(
            '🔄 🚨 MERGE DEBUG: Final range - Last: ${updatedMessages.last.createdAt} (${updatedMessages.last.id})');
      }
    } else {
      debugPrint('🔄 🚨 MERGE DEBUG: No changes detected, skipping UI update');
      debugPrint(
          '🔄 🚨 MERGE DEBUG: Cache preserved with ${optimisticMessages.length} messages');
    }
  }

  /// Perform additive merge to prevent cache truncation during partial server fetches
  void _performAdditiveMerge(
      String conversationId,
      List<Message> optimisticMessages,
      List<Message> serverMessages,
      Set<String> pending) {
    debugPrint(
        '🔄 ADDITIVE MERGE: Starting additive merge to prevent cache truncation');

    // Create a map of existing messages for fast lookup
    final existingMessageMap = <String, Message>{};
    for (final message in optimisticMessages) {
      existingMessageMap[message.id] = message;
    }

    // Start with all existing messages to prevent loss
    final mergedMessages = <Message>[...optimisticMessages];
    var hasChanges = false;

    // Update existing messages and add new ones from server
    for (final serverMessage in serverMessages) {
      final existingIndex =
          mergedMessages.indexWhere((m) => m.id == serverMessage.id);

      if (existingIndex != -1) {
        // Update existing message with preserved status
        final existingMessage = mergedMessages[existingIndex];
        final preservedStatus =
            _getBetterStatus(existingMessage.status, serverMessage.status);

        // Only update if there are actual changes
        if (existingMessage.status != preservedStatus ||
            existingMessage.content != serverMessage.content ||
            existingMessage.updatedAt != serverMessage.updatedAt) {
          final updatedMessage =
              serverMessage.copyWith(status: preservedStatus);
          mergedMessages[existingIndex] = updatedMessage;
          hasChanges = true;

          debugPrint(
              '🔄 ADDITIVE MERGE: Updated existing message ${serverMessage.id}');
        }
      } else {
        // New message from server - add it
        mergedMessages.add(serverMessage);
        hasChanges = true;
        debugPrint('🔄 ADDITIVE MERGE: Added new message ${serverMessage.id}');
      }
    }

    // Only update cache and emit if there were changes
    if (hasChanges) {
      // Sort messages chronologically
      mergedMessages.sort((a, b) {
        final timeComparison = a.createdAt.compareTo(b.createdAt);
        if (timeComparison == 0) {
          return a.id.compareTo(b.id);
        }
        return timeComparison;
      });

      // Update cache and emit
      _optimisticMessages[conversationId] = mergedMessages;
      _optimisticMessageStreams[conversationId]?.add(List.from(mergedMessages));

      debugPrint(
          '🔄 ADDITIVE MERGE: Completed - preserved ${optimisticMessages.length} cached messages, merged ${serverMessages.length} server messages, final count: ${mergedMessages.length}');
    } else {
      debugPrint(
          '🔄 ADDITIVE MERGE: No changes detected, cache preserved unchanged');
    }
  }

  /// Get the better status between optimistic and server status
  MessageStatus _getBetterStatus(
      MessageStatus optimistic, MessageStatus server) {
    // CRITICAL FIX: Always preserve "read" status once it's been set
    // This prevents race conditions where server merge overwrites read status
    if (optimistic == MessageStatus.read || server == MessageStatus.read) {
      debugPrint(
          '🎯 _getBetterStatus: ✅ PRESERVING READ STATUS (optimistic=$optimistic, server=$server) → READ');
      return MessageStatus.read;
    }

    // Priority: sent > delivered > sending > failed
    const statusPriority = {
      MessageStatus.sent: 4,
      MessageStatus.delivered: 3,
      MessageStatus.sending: 2,
      MessageStatus.failed: 1,
    };

    final optimisticPriority = statusPriority[optimistic] ?? 0;
    final serverPriority = statusPriority[server] ?? 0;

    final result = optimisticPriority >= serverPriority ? optimistic : server;

    // ENHANCED DEBUG: Log status priority decisions
    if (optimistic != server) {
      debugPrint(
          '🎯 _getBetterStatus: optimistic=$optimistic (priority=$optimisticPriority) vs server=$server (priority=$serverPriority) → result=$result');
    }

    return result;
  }

  /// Initialize subscription to message status updates
  void _initializeStatusSubscription() {
    try {
      debugPrint('🔧 OptimisticUI: Initializing status subscription...');
      debugPrint(
          '🔧 OptimisticUI: MessageStatusService instance: $_messageStatusService');

      _statusSubscription = _messageStatusService.statusUpdates.listen(
        (statusUpdate) {
          debugPrint(
              '🔔 OptimisticUI: Received status update for message ${statusUpdate.messageId}: ${statusUpdate.status}');
          _handleStatusUpdate(statusUpdate);
        },
        onError: (error) {
          debugPrint('❌ OptimisticUI: Error in status subscription: $error');
        },
      );
      debugPrint(
          '✅ OptimisticUI: Status subscription initialized successfully');
    } catch (error) {
      debugPrint(
          '❌ OptimisticUI: Failed to initialize status subscription: $error');
    }
  }

  /// Manually initialize status subscription (called from ConversationService)
  void ensureStatusSubscriptionInitialized() {
    if (_statusSubscription == null) {
      debugPrint(
          '🔧 OptimisticUI: Manually initializing status subscription...');
      _initializeStatusSubscription();
    } else {
      debugPrint('✅ OptimisticUI: Status subscription already initialized');
    }
  }

  /// Handle incoming status updates from MessageStatusService
  void _handleStatusUpdate(MessageStatusUpdate statusUpdate) {
    final messageId = statusUpdate.messageId;
    final newStatus = statusUpdate.status;

    debugPrint(
        '🔄 OptimisticUI: Processing status update for message $messageId: $newStatus');
    debugPrint(
        '🔄 OptimisticUI: Status update details - isOptimistic: ${statusUpdate.isOptimistic}, isConfirmed: ${statusUpdate.isConfirmed}');

    // Find which conversation this message belongs to
    String? targetConversationId;
    debugPrint(
        '🔍 OptimisticUI: Searching for message $messageId in ${_optimisticMessages.length} conversations');

    for (final entry in _optimisticMessages.entries) {
      final conversationId = entry.key;
      final messages = entry.value;

      if (messages.any((message) => message.id == messageId)) {
        targetConversationId = conversationId;
        debugPrint(
            '✅ OptimisticUI: Found message $messageId in conversation $conversationId');
        break;
      }
    }

    if (targetConversationId == null) {
      debugPrint(
          '❌ OptimisticUI: Message $messageId not found in any conversation');
    }

    if (targetConversationId != null) {
      final messages = _optimisticMessages[targetConversationId]!;
      final messageIndex = messages.indexWhere((m) => m.id == messageId);

      if (messageIndex != -1) {
        final currentMessage = messages[messageIndex];

        // Only update if status actually changed
        if (currentMessage.status != newStatus) {
          messages[messageIndex] = currentMessage.copyWith(status: newStatus);

          // Emit updated list to trigger UI rebuild
          _optimisticMessageStreams[targetConversationId]
              ?.add(List.from(messages));

          debugPrint(
              '✅ OptimisticUI: Updated message $messageId status from ${currentMessage.status} to $newStatus');
        } else {
          debugPrint(
              '🔄 OptimisticUI: Message $messageId already has status $newStatus, skipping update');
        }
      } else {
        debugPrint(
            '⚠️ OptimisticUI: Message $messageId not found in conversation $targetConversationId');
      }
    } else {
      debugPrint(
          '⚠️ OptimisticUI: Could not find conversation for message $messageId');
    }
  }

  /// Update read status instantly
  void updateReadStatusInstantly(
      String conversationId, List<String> messageIds) {
    final messages = _optimisticMessages[conversationId];
    final currentUserId = _supabase.auth.currentUser?.id;

    debugPrint(
        '⚡ OptimisticUI: updateReadStatusInstantly called for conversation $conversationId');
    debugPrint('⚡ OptimisticUI: messageIds to update: $messageIds');
    debugPrint('⚡ OptimisticUI: currentUserId: $currentUserId');
    debugPrint(
        '⚡ OptimisticUI: cached messages count: ${messages?.length ?? 0}');

    if (messages != null && currentUserId != null) {
      bool updated = false;

      for (int i = 0; i < messages.length; i++) {
        final isFromCurrentUser = messages[i].senderId == currentUserId;
        final isFromOther = !isFromCurrentUser;
        final isAlreadyRead = messages[i].status == MessageStatus.read;

        // REAL-TIME READ STATUS FIX: Update all unread messages from other users
        if (messageIds.isEmpty || messageIds.contains(messages[i].id)) {
          // Only update messages that are not already read and not from current user
          if (!isAlreadyRead && isFromOther) {
            messages[i] = messages[i].copyWith(status: MessageStatus.read);
            updated = true;
          }
        }
      }

      if (updated) {
        // Emit updated list instantly
        _optimisticMessageStreams[conversationId]?.add(List.from(messages));
        debugPrint(
            '⚡ OptimisticUI: Updated read status instantly for ${messageIds.length} messages');
        debugPrint(
            '🔔 OptimisticUI: EMITTING updated message list to stream with ${messages.length} messages');
      } else {
        debugPrint('⚡ OptimisticUI: No messages needed read status update');
      }
    } else {
      debugPrint(
          '⚡ OptimisticUI: No messages found for conversation $conversationId or no current user');
    }
  }

  /// Get pending message count for conversation
  int getPendingMessageCount(String conversationId) {
    return _pendingMessages[conversationId]?.length ?? 0;
  }

  /// Get failed message count for conversation
  int getFailedMessageCount(String conversationId) {
    return _failedMessages[conversationId]?.length ?? 0;
  }

  /// Retry failed message
  void retryFailedMessage(String conversationId, String messageId) {
    final failed = _failedMessages[conversationId];
    final pending = _pendingMessages[conversationId];

    if (failed != null && pending != null && failed.contains(messageId)) {
      failed.remove(messageId);
      pending.add(messageId);

      debugPrint('🔄 Retrying failed message: $messageId');
    }
  }

  /// Get cached messages for a conversation (for navigation persistence)
  List<Message> getCachedMessages(String conversationId) {
    final messages = _optimisticMessages[conversationId];
    if (messages != null) {
      debugPrint(
          '📋 🔍 CACHE DEBUG: Retrieved ${messages.length} cached messages for conversation: $conversationId');

      // ENHANCED DEBUG: Log message count and time range
      if (messages.isNotEmpty) {
        final firstMessage = messages.first;
        final lastMessage = messages.last;
        debugPrint(
            '📋 🔍 CACHE DEBUG: Message range - First: ${firstMessage.createdAt} (${firstMessage.id})');
        debugPrint(
            '📋 🔍 CACHE DEBUG: Message range - Last: ${lastMessage.createdAt} (${lastMessage.id})');

        // Count read messages for status tracking
        final readCount =
            messages.where((m) => m.status == MessageStatus.read).length;
        final sentCount =
            messages.where((m) => m.status == MessageStatus.sent).length;
        debugPrint(
            '📋 🔍 CACHE DEBUG: Status breakdown - Read: $readCount, Sent: $sentCount, Total: ${messages.length}');
      }

      return List.from(
          messages); // Return a copy to prevent external modification
    }
    debugPrint(
        '📋 🔍 CACHE DEBUG: No cached messages found for conversation: $conversationId');
    return [];
  }

  /// Clear optimistic data for conversation
  void clearConversation(String conversationId) {
    _optimisticMessageStreams[conversationId]?.close();
    _optimisticMessageStreams.remove(conversationId);
    _optimisticMessages.remove(conversationId);
    _pendingMessages.remove(conversationId);
    _failedMessages.remove(conversationId);

    debugPrint('🗑️ Cleared optimistic data for conversation: $conversationId');
  }

  /// Dispose all streams
  void dispose() {
    // Cancel status subscription
    _statusSubscription?.cancel();
    _statusSubscription = null;

    for (final controller in _optimisticMessageStreams.values) {
      controller.close();
    }
    _optimisticMessageStreams.clear();
    _optimisticMessages.clear();
    _pendingMessages.clear();
    _failedMessages.clear();

    debugPrint('🗑️ Disposed optimistic UI service');
  }

  /// Get service statistics
  Map<String, dynamic> getStats() {
    int totalOptimistic = 0;
    int totalPending = 0;
    int totalFailed = 0;

    for (final messages in _optimisticMessages.values) {
      totalOptimistic += messages.length;
    }

    for (final pending in _pendingMessages.values) {
      totalPending += pending.length;
    }

    for (final failed in _failedMessages.values) {
      totalFailed += failed.length;
    }

    return {
      'activeConversations': _optimisticMessageStreams.length,
      'totalOptimisticMessages': totalOptimistic,
      'totalPendingMessages': totalPending,
      'totalFailedMessages': totalFailed,
    };
  }
}
