import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/models/direct_message.dart';
import 'package:pulsemeet/models/chat_message.dart';
import 'package:pulsemeet/services/direct_message_service.dart';
import 'package:pulsemeet/widgets/chat/message_bubble.dart';
import 'package:pulsemeet/widgets/chat/message_input.dart';
import 'package:pulsemeet/widgets/chat/date_separator.dart';
import 'package:pulsemeet/widgets/chat/typing_indicator.dart';
import 'package:pulsemeet/widgets/avatar.dart';
import 'package:pulsemeet/screens/profile/user_profile_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

/// Screen for direct messaging with another user
class DirectMessageScreen extends StatefulWidget {
  final String otherUserId;
  final Profile? otherUserProfile;

  const DirectMessageScreen({
    super.key,
    required this.otherUserId,
    this.otherUserProfile,
  });

  @override
  State<DirectMessageScreen> createState() => _DirectMessageScreenState();
}

class _DirectMessageScreenState extends State<DirectMessageScreen> {
  final _directMessageService = DirectMessageService();
  final _scrollController = ScrollController();
  
  Profile? _otherUserProfile;
  List<DirectMessage> _messages = [];
  DirectMessage? _replyToMessage;
  bool _isOtherUserTyping = false;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _otherUserProfile = widget.otherUserProfile;
    _initializeChat();
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  /// Initialize the chat
  Future<void> _initializeChat() async {
    setState(() {
      _isLoading = true;
    });
    
    // Subscribe to messages
    await _directMessageService.subscribeToMessages(widget.otherUserId);
    
    // Subscribe to typing status
    await _directMessageService.subscribeToTypingStatus(widget.otherUserId);
    
    // Listen for new messages
    _directMessageService.messagesStream.listen((messagesMap) {
      if (mounted) {
        setState(() {
          _messages = messagesMap[widget.otherUserId] ?? [];
          _isLoading = false;
        });
        
        // Scroll to bottom when new messages arrive
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
    
    // Listen for typing status
    _directMessageService.typingStatusStream.listen((typingStatusMap) {
      if (mounted) {
        setState(() {
          _isOtherUserTyping = typingStatusMap[widget.otherUserId] ?? false;
        });
      }
    });
    
    // Fetch other user profile if not provided
    if (_otherUserProfile == null) {
      try {
        final supabase = Supabase.instance.client;
        final response = await supabase
            .from('profiles')
            .select()
            .eq('id', widget.otherUserId)
            .single();
        
        if (mounted) {
          setState(() {
            _otherUserProfile = Profile.fromJson(response);
          });
        }
      } catch (e) {
        debugPrint('Error fetching other user profile: $e');
      }
    }
  }
  
  /// Handle sending a text message
  Future<void> _handleSendText(String text) async {
    if (text.trim().isEmpty) return;
    
    try {
      await _directMessageService.sendTextMessage(
        widget.otherUserId,
        text,
        replyToId: _replyToMessage?.id,
      );
      
      // Clear reply
      setState(() {
        _replyToMessage = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending message: ${e.toString()}')),
        );
      }
    }
  }
  
  /// Handle sending an image
  Future<void> _handleSendImage(File image, String? caption) async {
    try {
      await _directMessageService.sendImageMessage(
        widget.otherUserId,
        image,
        caption: caption,
        replyToId: _replyToMessage?.id,
      );
      
      // Clear reply
      setState(() {
        _replyToMessage = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending image: ${e.toString()}')),
        );
      }
    }
  }
  
  /// Handle canceling a reply
  void _handleCancelReply() {
    setState(() {
      _replyToMessage = null;
    });
  }
  
  /// Handle message tap
  void _handleMessageTap(DirectMessage message) {
    // No action for now
  }
  
  /// Handle message long press
  void _handleMessageLongPress(DirectMessage message) {
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
          if (message.senderId == Supabase.instance.client.auth.currentUser?.id)
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement delete functionality
              },
            ),
        ],
      ),
    );
  }
  
  /// Handle reaction tap
  void _handleReactionTap(String emoji) {
    // TODO: Implement reaction functionality
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            if (_otherUserProfile != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfileScreen(userId: widget.otherUserId),
                ),
              );
            }
          },
          child: Row(
            children: [
              UserAvatar(
                userId: widget.otherUserId,
                avatarUrl: _otherUserProfile?.avatarUrl,
                size: 36.0,
              ),
              const SizedBox(width: 8.0),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _otherUserProfile?.displayName ?? 
                    _otherUserProfile?.username ?? 
                    'User',
                    style: const TextStyle(fontSize: 16.0),
                  ),
                  if (_isOtherUserTyping)
                    const Text(
                      'typing...',
                      style: TextStyle(
                        fontSize: 12.0,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              if (_otherUserProfile != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(userId: widget.otherUserId),
                  ),
                );
              }
            },
            tooltip: 'View Profile',
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: _buildMessagesList(),
          ),
          
          // Typing indicator
          if (_isOtherUserTyping)
            Padding(
              padding: const EdgeInsets.only(left: 16.0, bottom: 4.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TypingIndicator(
                  typingUsers: [
                    _otherUserProfile ?? 
                    Profile(
                      id: widget.otherUserId,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                      lastSeenAt: DateTime.now(),
                    ),
                  ],
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          
          // Message input
          MessageInput(
            pulseId: widget.otherUserId, // Using otherUserId as pulseId for compatibility
            onSendText: _handleSendText,
            onSendImage: _handleSendImage,
            onSendVideo: (_, __) {}, // Not implemented yet
            onSendAudio: (_, __) {}, // Not implemented yet
            onSendLocation: (_) {}, // Not implemented yet
            onSendLiveLocation: (_, __) {}, // Not implemented yet
            onCancelReply: _handleCancelReply,
            replyToMessage: _replyToMessage != null 
                ? ChatMessage(
                    id: _replyToMessage!.id,
                    pulseId: widget.otherUserId,
                    senderId: _replyToMessage!.senderId,
                    senderName: _replyToMessage!.senderName,
                    senderAvatarUrl: _replyToMessage!.senderAvatarUrl,
                    messageType: _replyToMessage!.messageType,
                    content: _replyToMessage!.content,
                    createdAt: _replyToMessage!.createdAt,
                  )
                : null,
          ),
        ],
      ),
    );
  }
  
  Widget _buildMessagesList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 64.0,
              color: Colors.grey,
            ),
            const SizedBox(height: 16.0),
            const Text(
              'No messages yet',
              style: TextStyle(fontSize: 18.0),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            const Text(
              'Start a conversation by sending a message',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    // Group messages by date
    final groupedMessages = <String, List<DirectMessage>>{};
    for (final message in _messages) {
      final date = DateFormat('yyyy-MM-dd').format(message.createdAt);
      if (!groupedMessages.containsKey(date)) {
        groupedMessages[date] = [];
      }
      groupedMessages[date]!.add(message);
    }
    
    // Flatten the grouped messages with date separators
    final flattenedMessages = <Widget>[];
    final sortedDates = groupedMessages.keys.toList()..sort();
    
    for (final date in sortedDates) {
      // Add date separator
      flattenedMessages.add(DateSeparator(date: DateTime.parse(date)));
      
      // Add messages for this date
      final messages = groupedMessages[date]!;
      for (int i = 0; i < messages.length; i++) {
        final message = messages[i];
        final previousMessage = i > 0 ? messages[i - 1] : null;
        final nextMessage = i < messages.length - 1 ? messages[i + 1] : null;
        
        // Convert DirectMessage to ChatMessage for compatibility with MessageBubble
        final chatMessage = ChatMessage(
          id: message.id,
          pulseId: widget.otherUserId,
          senderId: message.senderId,
          senderName: message.senderName,
          senderAvatarUrl: message.senderAvatarUrl,
          messageType: message.messageType,
          content: message.content,
          isDeleted: message.isDeleted,
          createdAt: message.createdAt,
          status: message.status,
          isFormatted: message.isFormatted,
          mediaData: message.mediaData,
          locationData: message.locationData,
          replyToId: message.replyToId,
          editedAt: message.editedAt,
        );
        
        // Convert previous and next messages if they exist
        final previousChatMessage = previousMessage != null
            ? ChatMessage(
                id: previousMessage.id,
                pulseId: widget.otherUserId,
                senderId: previousMessage.senderId,
                messageType: previousMessage.messageType,
                content: previousMessage.content,
                createdAt: previousMessage.createdAt,
              )
            : null;
        
        final nextChatMessage = nextMessage != null
            ? ChatMessage(
                id: nextMessage.id,
                pulseId: widget.otherUserId,
                senderId: nextMessage.senderId,
                messageType: nextMessage.messageType,
                content: nextMessage.content,
                createdAt: nextMessage.createdAt,
              )
            : null;
        
        // Find reply message if this message is a reply
        DirectMessage? replyToMessage;
        if (message.replyToId != null) {
          replyToMessage = _messages.firstWhere(
            (m) => m.id == message.replyToId,
            orElse: () => DirectMessage(
              id: '',
              senderId: '',
              receiverId: '',
              messageType: 'text',
              content: 'Original message not found',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        }
        
        // Convert reply message to ChatMessage if it exists
        final replyToChatMessage = replyToMessage != null && replyToMessage.id.isNotEmpty
            ? ChatMessage(
                id: replyToMessage.id,
                pulseId: widget.otherUserId,
                senderId: replyToMessage.senderId,
                messageType: replyToMessage.messageType,
                content: replyToMessage.content,
                createdAt: replyToMessage.createdAt,
              )
            : null;
        
        flattenedMessages.add(
          MessageBubble(
            message: chatMessage,
            previousMessage: previousChatMessage,
            nextMessage: nextChatMessage,
            currentUserId: Supabase.instance.client.auth.currentUser!.id,
            onReactionTap: _handleReactionTap,
            onMessageTap: (_) => _handleMessageTap(message),
            onMessageLongPress: (_) => _handleMessageLongPress(message),
            replyToMessage: replyToChatMessage,
          ),
        );
      }
    }
    
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(8.0),
      children: flattenedMessages,
    );
  }
}
