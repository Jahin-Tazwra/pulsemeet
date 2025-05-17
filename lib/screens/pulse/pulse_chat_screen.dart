import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:animations/animations.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'package:pulsemeet/models/chat_message.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/chat_service.dart';
import 'package:pulsemeet/services/pulse_participant_service.dart';
import 'package:pulsemeet/widgets/chat/message_bubble.dart';
import 'package:pulsemeet/widgets/chat/message_input.dart';
import 'package:pulsemeet/widgets/chat/date_separator.dart';
import 'package:pulsemeet/widgets/chat/typing_indicator.dart';
import 'package:pulsemeet/widgets/chat/audio_recorder.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Screen for pulse chat
class PulseChatScreen extends StatefulWidget {
  final Pulse pulse;

  const PulseChatScreen({
    super.key,
    required this.pulse,
  });

  @override
  State<PulseChatScreen> createState() => _PulseChatScreenState();
}

class _PulseChatScreenState extends State<PulseChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final ChatService _chatService = ChatService();
  final PulseParticipantService _participantService = PulseParticipantService();

  List<ChatMessage> _messages = [];
  List<Profile> _typingUsers = [];
  bool _isLoading = true;
  String? _errorMessage;
  ChatMessage? _replyToMessage;

  @override
  void initState() {
    super.initState();
    _initChat();
    _subscribeToTypingStatus();
  }

  /// Subscribe to typing status
  void _subscribeToTypingStatus() {
    // Subscribe to typing status
    _participantService.subscribeToTypingStatus(widget.pulse.id);

    // Listen to typing status updates
    _typingSubscription =
        _participantService.typingUsersStream.listen((typingUsersMap) async {
      if (mounted) {
        // Skip if no one is typing
        if (typingUsersMap.isEmpty) {
          setState(() {
            _typingUsers = [];
          });
          return;
        }

        // Get the current user ID
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;

        // Get the profiles of typing users
        final typingUserIds = typingUsersMap.keys.toList();
        final participants =
            await _participantService.getParticipants(widget.pulse.id);

        // Filter out the current user and get profiles
        final typingProfiles = participants
            .where((profile) =>
                typingUserIds.contains(profile.id) &&
                profile.id != currentUserId)
            .toList();

        setState(() {
          _typingUsers = typingProfiles;
        });
      }
    });
  }

  @override
  void dispose() {
    // Cancel stream subscriptions
    _messagesSubscription?.cancel();
    _newMessageSubscription?.cancel();
    _messageStatusSubscription?.cancel();
    _typingSubscription?.cancel();

    // Unsubscribe from messages
    _chatService.unsubscribeFromMessages();

    // Dispose controllers
    _scrollController.dispose();

    super.dispose();
  }

  /// Initialize the chat
  Future<void> _initChat() async {
    // Set the current pulse ID and user ID
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId != null) {
      _chatService.setCurrentIds(widget.pulse.id, currentUserId);
    }

    // Subscribe to messages
    await _subscribeToMessages();

    // Load initial messages
    await _loadMessages();
  }

  // Track message status updates
  final Map<String, MessageStatus> _messageStatusMap = {};

  // Store stream subscriptions for cleanup
  StreamSubscription? _messagesSubscription;
  StreamSubscription? _newMessageSubscription;
  StreamSubscription? _messageStatusSubscription;
  StreamSubscription? _typingSubscription;

  /// Subscribe to messages
  Future<void> _subscribeToMessages() async {
    try {
      // Subscribe to the messages stream
      await _chatService.subscribeToMessages(widget.pulse.id);

      // Listen to the messages stream for all messages
      _messagesSubscription = _chatService.messagesStream.listen(
        (messages) {
          if (mounted) {
            setState(() {
              // Ensure messages are sorted by creation time (oldest first, newest last)
              messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
              _messages = messages;
              _isLoading = false;
            });

            // Mark messages as read when they arrive
            _chatService.markMessagesAsRead(widget.pulse.id);

            // Scroll to bottom when new messages arrive
            _scrollToBottom();
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Error loading messages: ${error.toString()}';
            });
          }
        },
      );

      // Listen to new messages for optimistic updates
      _newMessageSubscription = _chatService.newMessageStream.listen(
        (message) {
          if (mounted) {
            setState(() {
              // Check if the message already exists in our list
              final existingIndex =
                  _messages.indexWhere((m) => m.id == message.id);

              final bool isFromCurrentUser = message.senderId ==
                  Supabase.instance.client.auth.currentUser?.id;
              final bool isSending = message.status == MessageStatus.sending;

              if (existingIndex >= 0) {
                // Update existing message without changing its position
                _messages[existingIndex] = message;
                debugPrint(
                    'Updated existing message: ${message.id}, Status: ${message.status}');
              } else {
                // For messages that are being sent or from the current user
                if (isSending || isFromCurrentUser) {
                  // Always add these messages at the end to prevent jumping
                  _messages.add(message);
                  debugPrint(
                      'Added message at the end: ${message.id}, Status: ${message.status}, From current user: $isFromCurrentUser');
                } else {
                  // For messages from other users, insert in the correct chronological position
                  final insertIndex = _findInsertPosition(message);
                  _messages.insert(insertIndex, message);

                  // Play a sound or show a notification for new messages from others
                  debugPrint(
                      'New message received from ${message.senderName ?? "User"} at position $insertIndex');
                }
              }

              // Update message status in our tracking map
              _messageStatusMap[message.id] = message.status;
            });

            // Mark messages as read
            _chatService.markMessagesAsRead(widget.pulse.id);

            // Always scroll to bottom for new messages from the current user
            // or if the message is being sent
            if (message.senderId ==
                    Supabase.instance.client.auth.currentUser?.id ||
                message.status == MessageStatus.sending) {
              _scrollToBottom();
            }
          }
        },
        onError: (error) {
          debugPrint('Error with new message: ${error.toString()}');
        },
      );

      // Listen to message status updates
      _messageStatusSubscription = _chatService.messageStatusStream.listen(
        (messageId) {
          // Find the message and update its status
          final index = _messages.indexWhere((m) => m.id == messageId);
          if (index >= 0 && mounted) {
            setState(() {
              // The actual message status will be updated via the messages stream
              // This is just to trigger a UI update
              _messageStatusMap[messageId] = _messages[index].status;
            });
          }
        },
        onError: (error) {
          debugPrint('Error with message status: ${error.toString()}');
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error subscribing to messages: ${e.toString()}';
        });
      }
    }
  }

  /// Load initial messages
  Future<void> _loadMessages() async {
    try {
      final messages = await _chatService.getMessages(widget.pulse.id);

      if (mounted) {
        setState(() {
          // Ensure messages are sorted by creation time (oldest first, newest last)
          messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          _messages = messages;
          _isLoading = false;
        });

        // Mark messages as read
        _chatService.markMessagesAsRead(widget.pulse.id);

        // Scroll to bottom
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading messages: ${e.toString()}';
        });
      }
    }
  }

  /// Scroll to the bottom of the chat
  void _scrollToBottom() {
    // Use a microtask to ensure this happens after the UI is updated
    Future.microtask(() {
      if (mounted && _scrollController.hasClients) {
        try {
          // Add a small delay to ensure the layout is complete
          // Use a longer delay to ensure all messages are properly rendered
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && _scrollController.hasClients) {
              // Check if we're already near the bottom
              final double currentPosition = _scrollController.position.pixels;
              final double maxPosition =
                  _scrollController.position.maxScrollExtent;
              final bool isNearBottom = (maxPosition - currentPosition) < 200;

              // Use a smoother animation for better user experience
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: Duration(milliseconds: isNearBottom ? 200 : 300),
                curve: Curves.easeOutCubic,
              );

              // For extra reliability, check again after animation should be complete
              Future.delayed(const Duration(milliseconds: 350), () {
                if (mounted && _scrollController.hasClients) {
                  // If we're still not at the bottom, try one more time
                  if (_scrollController.position.pixels <
                      _scrollController.position.maxScrollExtent - 10) {
                    _scrollController
                        .jumpTo(_scrollController.position.maxScrollExtent);
                  }
                }
              });
            }
          });
        } catch (e) {
          // Ignore any errors that might occur during scrolling
          debugPrint('Error scrolling to bottom: $e');
        }
      }
    });
  }

  /// Find the correct position to insert a new message based on creation time
  int _findInsertPosition(ChatMessage newMessage) {
    // If the list is empty, insert at the beginning
    if (_messages.isEmpty) {
      return 0;
    }

    // For messages with status 'sending' or from the current user, always insert at the end
    // This ensures messages being sent always appear at the bottom and don't jump around
    if (newMessage.status == MessageStatus.sending ||
        newMessage.senderId == Supabase.instance.client.auth.currentUser?.id) {
      return _messages.length;
    }

    // For messages from other users, insert based on creation time
    // If the new message is newer than the last message, insert at the end
    if (newMessage.createdAt.isAfter(_messages.last.createdAt)) {
      return _messages.length;
    }

    // If the new message is older than the first message, insert at the beginning
    if (newMessage.createdAt.isBefore(_messages.first.createdAt)) {
      return 0;
    }

    // Otherwise, find the correct position using binary search
    int low = 0;
    int high = _messages.length - 1;

    while (low <= high) {
      int mid = (low + high) ~/ 2;

      if (_messages[mid].createdAt.isBefore(newMessage.createdAt)) {
        low = mid + 1;
      } else if (_messages[mid].createdAt.isAfter(newMessage.createdAt)) {
        high = mid - 1;
      } else {
        // If the creation times are equal, check if one is from current user
        final currentUserId =
            Supabase.instance.client.auth.currentUser?.id ?? '';
        final midFromCurrentUser = _messages[mid].senderId == currentUserId;
        final newFromCurrentUser = newMessage.senderId == currentUserId;

        // Current user's messages should appear after other messages with same timestamp
        if (!midFromCurrentUser && newFromCurrentUser) {
          return mid + 1;
        } else if (midFromCurrentUser && !newFromCurrentUser) {
          return mid;
        } else {
          // If both are from same sender, insert after this message
          return mid + 1;
        }
      }
    }

    // Insert at the low position
    return low;
  }

  /// Send a text message
  Future<void> _handleSendText(String text) async {
    try {
      // No need for a sending indicator anymore as the message will appear immediately
      // in the correct position via the newMessageStream
      debugPrint('Preparing to send text message...');

      // Send the message
      final message = await _chatService.sendTextMessage(
        widget.pulse.id,
        text,
        replyToId: _replyToMessage?.id,
      );

      // Clear reply
      if (mounted) {
        setState(() {
          _replyToMessage = null;
        });
      }

      // Handle failed message
      if (message != null && message.status == MessageStatus.failed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Message failed to send. It will be retried when you\'re back online.'),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () {
                  // Retry sending the message
                  _chatService.sendTextMessage(
                    widget.pulse.id,
                    text,
                    replyToId: _replyToMessage?.id,
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending message: ${e.toString()}')),
        );
      }
    }
  }

  /// Send an image message
  Future<void> _handleSendImage(File imageFile, String? caption) async {
    try {
      // No need for a sending indicator anymore as the message will appear immediately
      // in the correct position via the newMessageStream
      debugPrint('Preparing to send image message...');

      // Send the message
      final message = await _chatService.sendImageMessage(
        widget.pulse.id,
        imageFile,
        caption: caption,
        replyToId: _replyToMessage?.id,
      );

      // Clear reply
      if (mounted) {
        setState(() {
          _replyToMessage = null;
        });
      }

      // Handle failed message
      if (message != null && message.status == MessageStatus.failed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Image failed to send. It will be retried when you\'re back online.'),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () {
                  // Retry sending the image
                  _chatService.sendImageMessage(
                    widget.pulse.id,
                    imageFile,
                    caption: caption,
                    replyToId: _replyToMessage?.id,
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending image: ${e.toString()}')),
        );
      }
    }
  }

  /// Send a video message
  Future<void> _handleSendVideo(File videoFile, String? caption) async {
    try {
      // No need for a sending indicator anymore as the message will appear immediately
      // in the correct position via the newMessageStream
      debugPrint('Preparing to send video message...');

      // Send the message
      final message = await _chatService.sendVideoMessage(
        widget.pulse.id,
        videoFile,
        caption: caption,
        replyToId: _replyToMessage?.id,
      );

      // Clear reply
      if (mounted) {
        setState(() {
          _replyToMessage = null;
        });
      }

      // Handle failed message
      if (message != null && message.status == MessageStatus.failed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Video failed to send. It will be retried when you\'re back online.'),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () {
                  // Retry sending the video
                  _chatService.sendVideoMessage(
                    widget.pulse.id,
                    videoFile,
                    caption: caption,
                    replyToId: _replyToMessage?.id,
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending video: ${e.toString()}')),
        );
      }
    }
  }

  /// Send an audio message
  Future<void> _handleSendAudio(File audioFile, String? caption) async {
    try {
      // No need for a sending indicator anymore as the message will appear immediately
      // in the correct position via the newMessageStream
      debugPrint('Preparing to send audio message...');

      // Send the message
      final message = await _chatService.sendAudioMessage(
        widget.pulse.id,
        audioFile,
        caption: caption,
        replyToId: _replyToMessage?.id,
      );

      // Clear reply
      if (mounted) {
        setState(() {
          _replyToMessage = null;
        });
      }

      // Handle failed message
      if (message != null && message.status == MessageStatus.failed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Voice message failed to send. It will be retried when you\'re back online.'),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () {
                  // Retry sending the audio
                  _chatService.sendAudioMessage(
                    widget.pulse.id,
                    audioFile,
                    caption: caption,
                    replyToId: _replyToMessage?.id,
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error sending voice message: ${e.toString()}')),
        );
      }
    }
  }

  /// Send a location message
  Future<void> _handleSendLocation(String? caption) async {
    try {
      // No need for a sending indicator anymore as the message will appear immediately
      // in the correct position via the newMessageStream
      debugPrint('Preparing to send location message...');

      // Send the message
      final message = await _chatService.sendLocationMessage(
        widget.pulse.id,
        caption: caption,
        replyToId: _replyToMessage?.id,
      );

      // Clear reply
      if (mounted) {
        setState(() {
          _replyToMessage = null;
        });
      }

      // Handle failed message
      if (message != null && message.status == MessageStatus.failed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Location failed to send. It will be retried when you\'re back online.'),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () {
                  // Retry sending the location
                  _chatService.sendLocationMessage(
                    widget.pulse.id,
                    caption: caption,
                    replyToId: _replyToMessage?.id,
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending location: ${e.toString()}')),
        );
      }
    }
  }

  /// Send a live location message
  Future<void> _handleSendLiveLocation(
      String? caption, Duration duration) async {
    try {
      // No need for a sending indicator anymore as the message will appear immediately
      // in the correct position via the newMessageStream
      debugPrint('Preparing to send live location message...');

      // Send the message
      final message = await _chatService.sendLocationMessage(
        widget.pulse.id,
        caption: caption,
        replyToId: _replyToMessage?.id,
        isLive: true,
        shareDuration: duration,
      );

      // Clear reply
      if (mounted) {
        setState(() {
          _replyToMessage = null;
        });
      }

      // Handle failed message
      if (message != null && message.status == MessageStatus.failed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Live location failed to send. It will be retried when you\'re back online.'),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () {
                  // Retry sending the live location
                  _chatService.sendLocationMessage(
                    widget.pulse.id,
                    caption: caption,
                    replyToId: _replyToMessage?.id,
                    isLive: true,
                    shareDuration: duration,
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error sending live location: ${e.toString()}')),
        );
      }
    }
  }

  /// Handle message tap
  void _handleMessageTap(ChatMessage message) {
    // For now, just print the message
    debugPrint('Message tapped: ${message.id}');
  }

  /// Handle message long press
  void _handleMessageLongPress(ChatMessage message) {
    // Show options bottom sheet
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('Reply'),
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _replyToMessage = message;
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.emoji_emotions),
            title: const Text('React'),
            onTap: () {
              Navigator.pop(context);
              _showReactionPicker(message);
            },
          ),
          if (message.senderId == Supabase.instance.client.auth.currentUser?.id)
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(context);
                _showDeleteOptions(message);
              },
            ),
        ],
      ),
    );
  }

  /// Show reaction picker
  void _showReactionPicker(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose a reaction',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildReactionButton('👍', message),
                _buildReactionButton('❤️', message),
                _buildReactionButton('😂', message),
                _buildReactionButton('😮', message),
                _buildReactionButton('😢', message),
                _buildReactionButton('🙏', message),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build a reaction button
  Widget _buildReactionButton(String emoji, ChatMessage message) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _chatService.addReaction(message.id, emoji);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 30),
        ),
      ),
    );
  }

  /// Show delete options
  void _showDeleteOptions(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Delete for everyone'),
            onTap: () {
              Navigator.pop(context);
              _chatService.deleteMessage(message.id, forEveryone: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete for me'),
            onTap: () {
              Navigator.pop(context);
              _chatService.deleteMessage(message.id, forEveryone: false);
            },
          ),
        ],
      ),
    );
  }

  /// Handle reaction tap
  void _handleReactionTap(String messageId) {
    // Show reaction picker
    _showReactionPicker(_messages.firstWhere((m) => m.id == messageId));
  }

  /// Handle reply tap
  void _handleReplyTap(ChatMessage message) {
    // Scroll to the message
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index >= 0) {
      _scrollController.animateTo(
        index * 100.0, // Approximate height of a message
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Cancel reply
  void _handleCancelReply() {
    setState(() {
      _replyToMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pulse.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // Show pulse details
              // TODO: Implement pulse details screen
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: _buildMessagesList(),
          ),

          // Typing indicator
          if (_typingUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16.0, bottom: 4.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TypingIndicator(
                  typingUsers: _typingUsers,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),

          // Message input
          MessageInput(
            pulseId: widget.pulse.id,
            onSendText: _handleSendText,
            onSendImage: _handleSendImage,
            onSendVideo: _handleSendVideo,
            onSendAudio: _handleSendAudio,
            onSendLocation: _handleSendLocation,
            onSendLiveLocation: _handleSendLiveLocation,
            onCancelReply: _handleCancelReply,
            replyToMessage: _replyToMessage,
          ),
        ],
      ),
    );
  }

  /// Build the messages list
  Widget _buildMessagesList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initChat,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Center(
        child: Text('No messages yet. Start the conversation!'),
      );
    }

    // Use a builder to ensure we can scroll to bottom after the list is built
    return Builder(
      builder: (context) {
        // Schedule a scroll to bottom after the first build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });

        // Create a copy of messages to ensure we don't modify the original list
        final displayMessages = List<ChatMessage>.from(_messages);

        // Ensure messages are sorted by creation time (oldest first, newest last)
        // For messages with the same timestamp, prioritize current user's messages to appear last
        displayMessages.sort((a, b) {
          // First compare by creation time
          final timeComparison = a.createdAt.compareTo(b.createdAt);
          if (timeComparison != 0) return timeComparison;

          // If timestamps are equal, check if one is from current user
          final currentUserId =
              Supabase.instance.client.auth.currentUser?.id ?? '';
          final aFromCurrentUser = a.senderId == currentUserId;
          final bFromCurrentUser = b.senderId == currentUserId;

          // Current user's messages should appear after other messages with same timestamp
          if (aFromCurrentUser && !bFromCurrentUser) return 1;
          if (!aFromCurrentUser && bFromCurrentUser) return -1;

          // If both are from same sender, maintain original order
          return 0;
        });

        // Create a list of widgets that includes both messages and date separators
        final List<Widget> messageWidgets = [];
        DateTime? lastMessageDate;

        for (int i = 0; i < displayMessages.length; i++) {
          final message = displayMessages[i];
          final messageDate = DateTime(
            message.createdAt.year,
            message.createdAt.month,
            message.createdAt.day,
          );

          // Add date separator if this is a new day
          if (lastMessageDate == null || messageDate != lastMessageDate) {
            messageWidgets.add(
              PageTransitionSwitcher(
                transitionBuilder:
                    (child, primaryAnimation, secondaryAnimation) {
                  return FadeScaleTransition(
                    animation: primaryAnimation,
                    child: child,
                  );
                },
                child: DateSeparator(
                  key: ValueKey('date_$messageDate'),
                  date: messageDate,
                ),
              ),
            );
            lastMessageDate = messageDate;
          }

          // Get previous and next messages for grouping bubbles
          final previousMessage = i > 0 ? displayMessages[i - 1] : null;
          final nextMessage =
              i < displayMessages.length - 1 ? displayMessages[i + 1] : null;

          // Find the reply message if this is a reply
          ChatMessage? replyToMessage;
          if (message.replyToId != null) {
            replyToMessage = displayMessages.firstWhere(
              (m) => m.id == message.replyToId,
              orElse: () => message,
            );
          }

          // Get the current user ID
          final String currentUserId =
              Supabase.instance.client.auth.currentUser?.id ?? '';

          // Debug: Print message ownership information
          final bool isFromCurrentUser =
              message.isFromCurrentUser(currentUserId);
          debugPrint(
              'Message ID: ${message.id}, Content: "${message.content.substring(0, message.content.length > 10 ? 10 : message.content.length)}...", '
              'Sender ID: ${message.senderId}, Current User ID: $currentUserId, '
              'Is From Current User: $isFromCurrentUser');

          // Add the message bubble with animation
          messageWidgets.add(
            PageTransitionSwitcher(
              transitionBuilder: (child, primaryAnimation, secondaryAnimation) {
                return FadeScaleTransition(
                  animation: primaryAnimation,
                  child: child,
                );
              },
              child: MessageBubble(
                key: ValueKey(message.id),
                message: message,
                previousMessage: previousMessage,
                nextMessage: nextMessage,
                currentUserId: currentUserId,
                onReactionTap: _handleReactionTap,
                onMessageTap: _handleMessageTap,
                onMessageLongPress: _handleMessageLongPress,
                onReplyTap: _handleReplyTap,
                replyToMessage: replyToMessage,
              ),
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          // Use the combined list of messages and date separators
          itemCount: messageWidgets.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 2.0),
            child: messageWidgets[index],
          ),
        );
      },
    );
  }
}
