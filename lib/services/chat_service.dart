import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:pulsemeet/models/chat_message.dart';
import 'package:pulsemeet/models/formatted_text.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/media_service.dart';
import 'package:pulsemeet/services/location_service.dart';
import 'package:pulsemeet/services/audio_service.dart';
import 'package:pulsemeet/services/pulse_participant_service.dart';
import 'package:pulsemeet/services/notification_service.dart';

/// A service for handling chat functionality
class ChatService {
  static final ChatService _instance = ChatService._internal();

  factory ChatService() => _instance;

  ChatService._internal() {
    _initService();
  }

  final SupabaseClient _supabase = Supabase.instance.client;
  final MediaService _mediaService = MediaService();
  final LocationService _locationService = LocationService();
  final AudioService _audioService = AudioService();
  final NotificationService _notificationService = NotificationService();
  final PulseParticipantService _participantService = PulseParticipantService();
  final Uuid _uuid = const Uuid();

  // Stream controllers
  final StreamController<List<ChatMessage>> _messagesController =
      StreamController<List<ChatMessage>>.broadcast();
  final StreamController<ChatMessage> _newMessageController =
      StreamController<ChatMessage>.broadcast();
  final StreamController<String> _messageStatusController =
      StreamController<String>.broadcast();

  // Subscriptions
  StreamSubscription<List<Map<String, dynamic>>>? _messagesSubscription;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // State
  bool _isInitialized = false;
  bool _isOnline = true;
  String? _currentPulseId;
  String? _currentUserId;
  List<ChatMessage> _offlineQueue = [];

  // Getters
  Stream<List<ChatMessage>> get messagesStream => _messagesController.stream;
  Stream<ChatMessage> get newMessageStream => _newMessageController.stream;
  Stream<String> get messageStatusStream => _messageStatusController.stream;

  /// Initialize the service
  Future<void> _initService() async {
    if (_isInitialized) return;

    // Load offline queue
    await _loadOfflineQueue();

    // Listen for connectivity changes
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      final bool wasOnline = _isOnline;
      _isOnline = result != ConnectivityResult.none;

      // If we just came back online, process the offline queue
      if (!wasOnline && _isOnline) {
        _processOfflineQueue();
      }
    });

    // Check initial connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    _isOnline = connectivityResult != ConnectivityResult.none;

    _isInitialized = true;
  }

  /// Set the current pulse ID and user ID
  void setCurrentIds(String pulseId, String userId) {
    _currentPulseId = pulseId;
    _currentUserId = userId;
  }

  /// Subscribe to messages for a specific pulse
  Future<void> subscribeToMessages(String pulseId) async {
    // Unsubscribe from previous subscription
    await unsubscribeFromMessages();

    // Set current pulse ID
    _currentPulseId = pulseId;

    try {
      // Set up real-time subscription using the stream API
      // This approach is more reliable and handles reconnections automatically
      _supabase.auth.onAuthStateChange.listen((data) {
        // If auth state changes, refresh messages
        if (_currentPulseId == pulseId) {
          _refreshMessages(pulseId);
        }
      });

      // Set up a periodic refresh as a fallback
      // This ensures messages are updated even if real-time fails
      final refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (_currentPulseId != pulseId) {
          timer.cancel();
          _refreshTimers.remove(pulseId);
          return;
        }

        if (_isOnline) {
          _refreshMessages(pulseId);
        }
      });

      // Store the timer for cleanup
      _refreshTimers[pulseId] = refreshTimer;

      // Also subscribe to the traditional stream for initial data and backup
      _messagesSubscription = _supabase
          .from('chat_messages')
          .stream(primaryKey: ['id'])
          .eq('pulse_id', pulseId)
          .order('created_at',
              ascending: true) // Ensure consistent ascending order
          .listen((List<Map<String, dynamic>> data) {
            final List<ChatMessage> messages =
                data.map((message) => ChatMessage.fromJson(message)).toList();

            _messagesController.add(messages);
          }, onError: (error) {
            debugPrint('Error subscribing to messages stream: $error');
            // Try to refresh messages manually if the stream fails
            _refreshMessages(pulseId);
          });
    } catch (e) {
      debugPrint('Error setting up real-time subscriptions: $e');
      // Fallback to manual refresh
      _refreshMessages(pulseId);
    }
  }

  /// Refresh messages manually
  Future<void> _refreshMessages(String pulseId) async {
    try {
      final messages = await getMessages(pulseId);
      _messagesController.add(messages);
    } catch (e) {
      debugPrint('Error refreshing messages: $e');
    }
  }

  // Store timers for cleanup
  final Map<String, Timer> _refreshTimers = {};

  /// Unsubscribe from messages
  Future<void> unsubscribeFromMessages() async {
    // Cancel message subscription
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;

    // Cancel refresh timer if exists
    if (_currentPulseId != null &&
        _refreshTimers.containsKey(_currentPulseId)) {
      _refreshTimers[_currentPulseId]?.cancel();
      _refreshTimers.remove(_currentPulseId);
    }

    _currentPulseId = null;
  }

  /// Get messages for a specific pulse
  Future<List<ChatMessage>> getMessages(String pulseId,
      {int limit = 50, int offset = 0}) async {
    try {
      final response = await _supabase
          .from('chat_messages')
          .select()
          .eq('pulse_id', pulseId)
          .order('created_at', ascending: true) // Changed to ascending order
          .range(offset, offset + limit - 1);

      final List<ChatMessage> messages = response
          .map<ChatMessage>((message) => ChatMessage.fromJson(message))
          .toList();

      return messages; // No need to reverse the list
    } catch (e) {
      debugPrint('Error getting messages: $e');
      return [];
    }
  }

  /// Send a text message
  Future<ChatMessage?> sendTextMessage(
    String pulseId,
    String content, {
    bool isFormatted = false,
    String? replyToId,
  }) async {
    if (_currentUserId == null) return null;

    final String messageId = _uuid.v4();
    final DateTime now = DateTime.now();

    final ChatMessage message = ChatMessage(
      id: messageId,
      pulseId: pulseId,
      senderId: _currentUserId!,
      messageType: 'text',
      content: content,
      createdAt: now,
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
      // This ensures the message appears in the right position from the start
      _newMessageController.add(message);

      // Send message to server
      final response = await _supabase
          .from('chat_messages')
          .insert({
            'id': messageId,
            'pulse_id': pulseId,
            'sender_id': _currentUserId,
            'message_type': 'text',
            'content': content,
            'created_at': now.toIso8601String(),
            'is_formatted': isFormatted,
            'reply_to_id': replyToId,
            'status': 'sent',
          })
          .select()
          .single();

      // Update message status
      final sentMessage = ChatMessage.fromJson(response);
      _messageStatusController.add(messageId);

      // Process mentions if the message contains any
      if (content.contains('@')) {
        // Check if the message has mentions
        final formattedText = FormattedText.fromString(content);
        if (formattedText.segments
            .any((s) => s.type == FormattedSegmentType.mention)) {
          // Convert to formatted text if it contains mentions
          if (!isFormatted) {
            // Update the message to mark it as formatted
            await _supabase.from('chat_messages').update({
              'is_formatted': true,
              'content': formattedText.encode(),
            }).eq('id', messageId);
          }

          // Process mentions and send notifications
          await _notificationService.processMentions(sentMessage);
        }
      }

      return sentMessage;
    } catch (e) {
      debugPrint('Error sending text message: $e');

      // Add to offline queue if failed
      final failedMessage =
          message.copyWith(status: MessageStatus.failed, isOffline: true);
      _addToOfflineQueue(failedMessage);

      return failedMessage;
    }
  }

  /// Send an image message
  Future<ChatMessage?> sendImageMessage(
    String pulseId,
    File imageFile, {
    String? caption,
    String? replyToId,
  }) async {
    if (_currentUserId == null) return null;

    final String messageId = _uuid.v4();
    final DateTime now = DateTime.now();

    // Create a temporary message with loading status and local file path as media data
    // This ensures the image can be displayed immediately while uploading
    final MediaData tempMediaData = MediaData(
      url: 'file://${imageFile.path}',
      thumbnailUrl: null,
      mimeType: 'image/${imageFile.path.split('.').last}',
      size: imageFile.lengthSync(),
      width: 0, // Will be updated after upload
      height: 0, // Will be updated after upload
      duration: null,
    );

    final ChatMessage tempMessage = ChatMessage(
      id: messageId,
      pulseId: pulseId,
      senderId: _currentUserId!,
      messageType: 'image',
      content: caption ?? '',
      createdAt: now,
      status: MessageStatus.sending,
      replyToId: replyToId,
      mediaData: tempMediaData, // Include media data with local file path
    );

    // Add temporary message to stream immediately to ensure it appears in the right position
    _newMessageController.add(tempMessage);

    // If offline, add to queue and return
    if (!_isOnline) {
      final offlineMessage = tempMessage.copyWith(
        status: MessageStatus.failed,
        isOffline: true,
      );
      _addToOfflineQueue(offlineMessage);
      _newMessageController.add(offlineMessage);
      return offlineMessage;
    }

    try {
      // Upload image
      final MediaData? mediaData =
          await _mediaService.uploadMedia(imageFile, pulseId);

      if (mediaData == null) {
        throw Exception('Failed to upload image');
      }

      // Send message to server
      final response = await _supabase
          .from('chat_messages')
          .insert({
            'id': messageId,
            'pulse_id': pulseId,
            'sender_id': _currentUserId,
            'message_type': 'image',
            'content': caption ?? '',
            'created_at': now.toIso8601String(),
            'media_data': jsonEncode(mediaData.toJson()),
            'reply_to_id': replyToId,
            'status': 'sent',
          })
          .select()
          .single();

      // Update message status
      final sentMessage = ChatMessage.fromJson(response);
      _messageStatusController.add(messageId);

      // Process mentions in caption if any
      if (caption != null && caption.contains('@')) {
        // Check if the caption has mentions
        final formattedText = FormattedText.fromString(caption);
        if (formattedText.segments
            .any((s) => s.type == FormattedSegmentType.mention)) {
          // Process mentions and send notifications
          await _notificationService.processMentions(sentMessage);
        }
      }

      return sentMessage;
    } catch (e) {
      debugPrint('Error sending image message: $e');

      // Add to offline queue if failed
      final failedMessage = tempMessage.copyWith(
        status: MessageStatus.failed,
        isOffline: true,
      );
      _addToOfflineQueue(failedMessage);

      return failedMessage;
    }
  }

  /// Send a video message
  Future<ChatMessage?> sendVideoMessage(
    String pulseId,
    File videoFile, {
    String? caption,
    String? replyToId,
  }) async {
    if (_currentUserId == null) return null;

    final String messageId = _uuid.v4();
    final DateTime now = DateTime.now();

    // Create a temporary message with loading status and local file path as media data
    // This ensures the video can be displayed immediately while uploading
    final MediaData tempMediaData = MediaData(
      url: 'file://${videoFile.path}',
      thumbnailUrl: null,
      mimeType: 'video/${videoFile.path.split('.').last}',
      size: videoFile.lengthSync(),
      width: 0, // Will be updated after upload
      height: 0, // Will be updated after upload
      duration: null,
    );

    final ChatMessage tempMessage = ChatMessage(
      id: messageId,
      pulseId: pulseId,
      senderId: _currentUserId!,
      messageType: 'video',
      content: caption ?? '',
      createdAt: now,
      status: MessageStatus.sending,
      replyToId: replyToId,
      mediaData: tempMediaData, // Include media data with local file path
    );

    // Add temporary message to stream immediately to ensure it appears in the right position
    _newMessageController.add(tempMessage);

    // If offline, add to queue and return
    if (!_isOnline) {
      final offlineMessage = tempMessage.copyWith(
        status: MessageStatus.failed,
        isOffline: true,
      );
      _addToOfflineQueue(offlineMessage);
      _newMessageController.add(offlineMessage);
      return offlineMessage;
    }

    try {
      // Upload video
      final MediaData? mediaData =
          await _mediaService.uploadMedia(videoFile, pulseId);

      if (mediaData == null) {
        throw Exception('Failed to upload video');
      }

      // Send message to server
      final response = await _supabase
          .from('chat_messages')
          .insert({
            'id': messageId,
            'pulse_id': pulseId,
            'sender_id': _currentUserId,
            'message_type': 'video',
            'content': caption ?? '',
            'created_at': now.toIso8601String(),
            'media_data': jsonEncode(mediaData.toJson()),
            'reply_to_id': replyToId,
            'status': 'sent',
          })
          .select()
          .single();

      // Update message status
      final sentMessage = ChatMessage.fromJson(response);
      _messageStatusController.add(messageId);

      // Process mentions in caption if any
      if (caption != null && caption.contains('@')) {
        // Check if the caption has mentions
        final formattedText = FormattedText.fromString(caption);
        if (formattedText.segments
            .any((s) => s.type == FormattedSegmentType.mention)) {
          // Process mentions and send notifications
          await _notificationService.processMentions(sentMessage);
        }
      }

      return sentMessage;
    } catch (e) {
      debugPrint('Error sending video message: $e');

      // Add to offline queue if failed
      final failedMessage = tempMessage.copyWith(
        status: MessageStatus.failed,
        isOffline: true,
      );
      _addToOfflineQueue(failedMessage);

      return failedMessage;
    }
  }

  /// Send an audio message
  Future<ChatMessage?> sendAudioMessage(
    String pulseId,
    File audioFile, {
    String? caption,
    String? replyToId,
  }) async {
    if (_currentUserId == null) return null;

    final String messageId = _uuid.v4();
    final DateTime now = DateTime.now();

    // Create a temporary message with loading status and local file path as media data
    // This ensures the audio can be displayed immediately while uploading
    final MediaData tempMediaData = MediaData(
      url: 'file://${audioFile.path}',
      thumbnailUrl: null,
      mimeType: 'audio/mpeg',
      size: audioFile.lengthSync(),
      width: 0,
      height: 0,
      duration: null, // Will be updated after upload
    );

    final ChatMessage tempMessage = ChatMessage(
      id: messageId,
      pulseId: pulseId,
      senderId: _currentUserId!,
      messageType: 'audio',
      content: caption ?? '',
      createdAt: now,
      status: MessageStatus.sending,
      replyToId: replyToId,
      mediaData: tempMediaData, // Include media data with local file path
    );

    // Add temporary message to stream immediately to ensure it appears in the right position
    _newMessageController.add(tempMessage);

    // If offline, add to queue and return
    if (!_isOnline) {
      final offlineMessage = tempMessage.copyWith(
        status: MessageStatus.failed,
        isOffline: true,
      );
      _addToOfflineQueue(offlineMessage);
      _newMessageController.add(offlineMessage);
      return offlineMessage;
    }

    try {
      // Upload audio
      final MediaData? mediaData =
          await _audioService.uploadAudio(audioFile, pulseId);

      if (mediaData == null) {
        throw Exception('Failed to upload audio');
      }

      // Send message to server
      final response = await _supabase
          .from('chat_messages')
          .insert({
            'id': messageId,
            'pulse_id': pulseId,
            'sender_id': _currentUserId,
            'message_type': 'audio',
            'content': caption ?? '',
            'created_at': now.toIso8601String(),
            'media_data': jsonEncode(mediaData.toJson()),
            'reply_to_id': replyToId,
            'status': 'sent',
          })
          .select()
          .single();

      // Update message status
      final sentMessage = ChatMessage.fromJson(response);
      _messageStatusController.add(messageId);

      // Process mentions in caption if any
      if (caption != null && caption.contains('@')) {
        // Check if the caption has mentions
        final formattedText = FormattedText.fromString(caption);
        if (formattedText.segments
            .any((s) => s.type == FormattedSegmentType.mention)) {
          // Process mentions and send notifications
          await _notificationService.processMentions(sentMessage);
        }
      }

      return sentMessage;
    } catch (e) {
      debugPrint('Error sending audio message: $e');

      // Add to offline queue if failed
      final failedMessage = tempMessage.copyWith(
        status: MessageStatus.failed,
        isOffline: true,
      );
      _addToOfflineQueue(failedMessage);

      return failedMessage;
    }
  }

  /// Send a location message
  Future<ChatMessage?> sendLocationMessage(
    String pulseId, {
    String? caption,
    String? replyToId,
    bool isLive = false,
    Duration? shareDuration,
  }) async {
    if (_currentUserId == null) return null;

    final String messageId = _uuid.v4();
    final DateTime now = DateTime.now();

    // Create a temporary message with loading status
    final ChatMessage tempMessage = ChatMessage(
      id: messageId,
      pulseId: pulseId,
      senderId: _currentUserId!,
      messageType: isLive ? 'liveLocation' : 'location',
      content: caption ?? '',
      createdAt: now,
      status: MessageStatus.sending,
      replyToId: replyToId,
    );

    // Add temporary message to stream with a small delay
    // This ensures the UI has time to prepare for the new message
    Future.delayed(const Duration(milliseconds: 50), () {
      _newMessageController.add(tempMessage);
    });

    // If offline, add to queue and return
    if (!_isOnline) {
      final offlineMessage = tempMessage.copyWith(
        status: MessageStatus.failed,
        isOffline: true,
      );
      _addToOfflineQueue(offlineMessage);
      _newMessageController.add(offlineMessage);
      return offlineMessage;
    }

    try {
      // Get location data
      final LocationData? locationData =
          await _locationService.createLocationData(
        isLive: isLive,
        expiresAfter: shareDuration,
      );

      if (locationData == null) {
        throw Exception('Failed to get location');
      }

      // Send message to server
      final response = await _supabase
          .from('chat_messages')
          .insert({
            'id': messageId,
            'pulse_id': pulseId,
            'sender_id': _currentUserId,
            'message_type': isLive ? 'liveLocation' : 'location',
            'content': caption ?? '',
            'created_at': now.toIso8601String(),
            'location_data': jsonEncode(locationData.toJson()),
            'reply_to_id': replyToId,
            'status': 'sent',
            'expires_at': locationData.expiresAt?.toIso8601String(),
          })
          .select()
          .single();

      // Update message status
      final sentMessage = ChatMessage.fromJson(response);
      _messageStatusController.add(messageId);

      // Process mentions in caption if any
      if (caption != null && caption.contains('@')) {
        // Check if the caption has mentions
        final formattedText = FormattedText.fromString(caption);
        if (formattedText.segments
            .any((s) => s.type == FormattedSegmentType.mention)) {
          // Process mentions and send notifications
          await _notificationService.processMentions(sentMessage);
        }
      }

      // Start live location updates if needed
      if (isLive && shareDuration != null) {
        _locationService.startLiveLocationSharing(
          pulseId,
          messageId,
          (LocationData updatedLocation) {
            _updateLiveLocation(messageId, updatedLocation);
          },
          shareDuration,
        );
      }

      return sentMessage;
    } catch (e) {
      debugPrint('Error sending location message: $e');

      // Add to offline queue if failed
      final failedMessage = tempMessage.copyWith(
        status: MessageStatus.failed,
        isOffline: true,
      );
      _addToOfflineQueue(failedMessage);

      return failedMessage;
    }
  }

  /// Update a live location
  Future<void> _updateLiveLocation(
      String messageId, LocationData locationData) async {
    try {
      await _supabase.from('chat_messages').update({
        'location_data': jsonEncode(locationData.toJson()),
      }).eq('id', messageId);
    } catch (e) {
      debugPrint('Error updating live location: $e');
    }
  }

  /// Add a reaction to a message
  Future<bool> addReaction(String messageId, String emoji) async {
    if (_currentUserId == null) return false;

    try {
      // Get current message
      final response = await _supabase
          .from('chat_messages')
          .select('reactions')
          .eq('id', messageId)
          .single();

      // Parse reactions
      List<MessageReaction> reactions = [];
      if (response['reactions'] != null) {
        if (response['reactions'] is String) {
          try {
            final List<dynamic> reactionsList =
                jsonDecode(response['reactions']);
            reactions = reactionsList
                .map((reaction) => MessageReaction.fromJson(reaction))
                .toList();
          } catch (e) {
            // Handle parsing error
          }
        }
      }

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
      await _supabase.from('chat_messages').update({
        'reactions': jsonEncode(reactions.map((r) => r.toJson()).toList()),
      }).eq('id', messageId);

      return true;
    } catch (e) {
      debugPrint('Error adding reaction: $e');
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
            .from('chat_messages')
            .update({
              'is_deleted': true,
              'content': '',
              'media_data': null,
              'location_data': null,
            })
            .eq('id', messageId)
            .eq('sender_id', _currentUserId);
      } else {
        // TODO: Implement delete for me only (would require a separate table)
        // For now, just mark as deleted for everyone
        await _supabase
            .from('chat_messages')
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
      debugPrint('Error deleting message: $e');
      return false;
    }
  }

  /// Mark messages as read
  Future<bool> markMessagesAsRead(String pulseId) async {
    if (_currentUserId == null) return false;

    try {
      // Get all unread messages for this pulse
      final response = await _supabase
          .from('chat_messages')
          .select('id')
          .eq('pulse_id', pulseId)
          .neq('sender_id', _currentUserId)
          .eq('status', 'sent')
          .order('created_at', ascending: false)
          .limit(100);

      if (response.isEmpty) return true;

      // Get message IDs
      final List<String> messageIds =
          response.map<String>((m) => m['id'] as String).toList();

      // Update message status to 'read' in a batch
      for (final messageId in messageIds) {
        await _supabase.from('chat_messages').update({
          'status': 'read',
        }).eq('id', messageId);

        // Notify status change
        _messageStatusController.add(messageId);
      }

      return true;
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
      return false;
    }
  }

  /// Add a message to the offline queue
  void _addToOfflineQueue(ChatMessage message) {
    _offlineQueue.add(message);
    _saveOfflineQueue();
  }

  /// Process the offline queue
  Future<void> _processOfflineQueue() async {
    if (_offlineQueue.isEmpty) return;

    // Show a notification that we're processing offline messages
    debugPrint('Processing ${_offlineQueue.length} offline messages');

    final List<ChatMessage> queue = List.from(_offlineQueue);
    _offlineQueue.clear();
    await _saveOfflineQueue();

    for (final message in queue) {
      try {
        // Update message status to sending
        final updatedMessage = message.copyWith(
          status: MessageStatus.sending,
          isOffline: false,
        );
        _newMessageController.add(updatedMessage);

        switch (message.messageType) {
          case 'text':
            await sendTextMessage(
              message.pulseId,
              message.content,
              isFormatted: message.isFormatted,
              replyToId: message.replyToId,
            );
            break;

          case 'image':
          case 'video':
            // For media messages, we need to check if we have the file path stored
            if (message.mediaData != null &&
                message.mediaData!.url.startsWith('file://')) {
              // Extract the local file path
              final String filePath =
                  message.mediaData!.url.replaceFirst('file://', '');
              final File file = File(filePath);

              if (await file.exists()) {
                if (message.messageType == 'image') {
                  await sendImageMessage(
                    message.pulseId,
                    file,
                    caption: message.content,
                    replyToId: message.replyToId,
                  );
                } else {
                  await sendVideoMessage(
                    message.pulseId,
                    file,
                    caption: message.content,
                    replyToId: message.replyToId,
                  );
                }
              } else {
                // File doesn't exist anymore, mark as failed
                final failedMessage = message.copyWith(
                  status: MessageStatus.failed,
                );
                _newMessageController.add(failedMessage);
              }
            }
            break;

          case 'location':
          case 'liveLocation':
            // For location messages, we can just send a new location
            await sendLocationMessage(
              message.pulseId,
              caption: message.content,
              replyToId: message.replyToId,
              isLive: message.messageType == 'liveLocation',
              shareDuration: message.expiresAt != null
                  ? DateTime.now().difference(message.expiresAt!)
                  : null,
            );
            break;

          default:
            // Skip other message types
            break;
        }
      } catch (e) {
        debugPrint('Error processing offline message: $e');
        // Mark as failed
        final failedMessage = message.copyWith(
          status: MessageStatus.failed,
        );
        _newMessageController.add(failedMessage);
      }
    }
  }

  /// Save the offline queue to shared preferences
  Future<void> _saveOfflineQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> encodedMessages =
          _offlineQueue.map((message) => jsonEncode(message.toJson())).toList();

      await prefs.setStringList('offline_message_queue', encodedMessages);
    } catch (e) {
      debugPrint('Error saving offline queue: $e');
    }
  }

  /// Load the offline queue from shared preferences
  Future<void> _loadOfflineQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? encodedMessages =
          prefs.getStringList('offline_message_queue');

      if (encodedMessages != null) {
        _offlineQueue = encodedMessages
            .map((encoded) => ChatMessage.fromJson(jsonDecode(encoded)))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading offline queue: $e');
      _offlineQueue = [];
    }
  }

  /// Dispose all resources
  void dispose() {
    // Cancel all subscriptions
    _messagesSubscription?.cancel();
    _connectivitySubscription?.cancel();

    // Cancel all refresh timers
    for (final timer in _refreshTimers.values) {
      timer.cancel();
    }
    _refreshTimers.clear();

    // Close all stream controllers
    _messagesController.close();
    _newMessageController.close();
    _messageStatusController.close();

    // Dispose other services
    _locationService.dispose();
  }
}
