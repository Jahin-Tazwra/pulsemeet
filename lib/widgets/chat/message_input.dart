import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pulsemeet/models/chat_message.dart';
import 'package:pulsemeet/services/media_service.dart';
import 'package:pulsemeet/services/location_service.dart';
import 'package:pulsemeet/services/audio_service.dart';
import 'package:pulsemeet/services/pulse_participant_service.dart';
import 'package:pulsemeet/widgets/chat/attachment_options.dart';
import 'package:pulsemeet/widgets/chat/mention_text_input.dart';
import 'package:pulsemeet/widgets/chat/audio_recorder.dart';

/// A widget for composing and sending messages
class MessageInput extends StatefulWidget {
  final String pulseId;
  final Function(String) onSendText;
  final Function(File, String?) onSendImage;
  final Function(File, String?) onSendVideo;
  final Function(File, String?) onSendAudio;
  final Function(String?) onSendLocation;
  final Function(String?, Duration) onSendLiveLocation;
  final Function() onCancelReply;
  final ChatMessage? replyToMessage;

  const MessageInput({
    super.key,
    required this.pulseId,
    required this.onSendText,
    required this.onSendImage,
    required this.onSendVideo,
    required this.onSendAudio,
    required this.onSendLocation,
    required this.onSendLiveLocation,
    required this.onCancelReply,
    this.replyToMessage,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final MediaService _mediaService = MediaService();
  final LocationService _locationService = LocationService();
  final AudioService _audioService = AudioService();
  final PulseParticipantService _participantService = PulseParticipantService();

  bool _isComposing = false;
  bool _showAttachmentOptions = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_handleTextChanged);

    // Subscribe to typing status for this pulse
    _participantService.subscribeToTypingStatus(widget.pulseId);
  }

  @override
  void dispose() {
    _textController.removeListener(_handleTextChanged);
    _textController.dispose();
    _focusNode.dispose();

    // Cancel recording if active when disposed
    if (_isRecording) {
      _audioService.cancelRecording();
    }

    super.dispose();
  }

  /// Handle text changes - now handled by MentionTextInput
  void _handleTextChanged() {
    // Composing state is now handled by MentionTextInput
  }

  /// Send a text message
  void _handleSendText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    widget.onSendText(text);
    _textController.clear();
    setState(() {
      _isComposing = false;
    });
  }

  /// Toggle attachment options
  void _toggleAttachmentOptions() {
    setState(() {
      _showAttachmentOptions = !_showAttachmentOptions;
    });
  }

  /// Handle image selection
  Future<void> _handleImageSelection(ImageSource source) async {
    setState(() {
      _showAttachmentOptions = false;
    });

    File? imageFile;
    if (source == ImageSource.camera) {
      imageFile = await _mediaService.takePhoto();
    } else {
      imageFile = await _mediaService.pickImageFromGallery();
    }

    if (imageFile != null && mounted) {
      widget.onSendImage(imageFile, _textController.text.trim());
      _textController.clear();
      setState(() {
        _isComposing = false;
      });
    }
  }

  /// Handle video selection
  Future<void> _handleVideoSelection(ImageSource source) async {
    setState(() {
      _showAttachmentOptions = false;
    });

    File? videoFile;
    if (source == ImageSource.camera) {
      videoFile = await _mediaService.recordVideo();
    } else {
      videoFile = await _mediaService.pickVideoFromGallery();
    }

    if (videoFile != null && mounted) {
      widget.onSendVideo(videoFile, _textController.text.trim());
      _textController.clear();
      setState(() {
        _isComposing = false;
      });
    }
  }

  /// Handle location sharing
  Future<void> _handleLocationSharing() async {
    setState(() {
      _showAttachmentOptions = false;
    });

    final position = await _locationService.getCurrentLocation();
    if (position != null && mounted) {
      widget.onSendLocation(_textController.text.trim());
      _textController.clear();
      setState(() {
        _isComposing = false;
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not access your location'),
        ),
      );
    }
  }

  /// Handle live location sharing
  Future<void> _handleLiveLocationSharing(Duration duration) async {
    setState(() {
      _showAttachmentOptions = false;
    });

    final position = await _locationService.getCurrentLocation();
    if (position != null && mounted) {
      widget.onSendLiveLocation(_textController.text.trim(), duration);
      _textController.clear();
      setState(() {
        _isComposing = false;
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not access your location'),
        ),
      );
    }
  }

  /// Show live location duration options
  void _showLiveLocationOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Share for 15 minutes'),
            onTap: () {
              Navigator.pop(context);
              _handleLiveLocationSharing(const Duration(minutes: 15));
            },
          ),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Share for 1 hour'),
            onTap: () {
              Navigator.pop(context);
              _handleLiveLocationSharing(const Duration(hours: 1));
            },
          ),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Share for 8 hours'),
            onTap: () {
              Navigator.pop(context);
              _handleLiveLocationSharing(const Duration(hours: 8));
            },
          ),
        ],
      ),
    );
  }

  /// Handle long press on mic button to start recording
  void _handleMicButtonLongPress() async {
    debugPrint('Long press detected on mic button');

    // Request microphone permission first
    final hasPermission = await _audioService.requestMicrophonePermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Microphone permission is required to record voice messages'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Start recording UI
    setState(() {
      _isRecording = true;
    });
  }

  /// Handle release of mic button to stop recording
  void _handleMicButtonLongPressEnd(LongPressEndDetails details) {
    // This is now handled by the AudioRecorderWidget
    // We keep this method for compatibility with the GestureDetector
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Reply indicator
        if (widget.replyToMessage != null) _buildReplyIndicator(),

        // Attachment options
        if (_showAttachmentOptions)
          AttachmentOptions(
            onImageFromCamera: () => _handleImageSelection(ImageSource.camera),
            onImageFromGallery: () =>
                _handleImageSelection(ImageSource.gallery),
            onVideoFromCamera: () => _handleVideoSelection(ImageSource.camera),
            onVideoFromGallery: () =>
                _handleVideoSelection(ImageSource.gallery),
            onLocation: _handleLocationSharing,
            onLiveLocation: _showLiveLocationOptions,
          ),

        // Input bar
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withAlpha(13), // Using withAlpha instead of withOpacity
                blurRadius: 3,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 8.0,
            vertical: 8.0,
          ),
          child: _isRecording
              ? _buildRecordingUI()
              : Row(
                  children: [
                    // Attachment button
                    IconButton(
                      icon: Icon(
                        _showAttachmentOptions
                            ? Icons.close
                            : Icons.attach_file,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      onPressed: _toggleAttachmentOptions,
                    ),

                    // Text field with mention support
                    Expanded(
                      child: MentionTextInput(
                        controller: _textController,
                        focusNode: _focusNode,
                        pulseId: widget.pulseId,
                        onComposingChanged: (isComposing) {
                          setState(() {
                            _isComposing = isComposing;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Type a message',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24.0),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 5,
                        minLines: 1,
                      ),
                    ),

                    // Send/Mic button
                    GestureDetector(
                      onLongPress: _handleMicButtonLongPress,
                      onLongPressEnd: _handleMicButtonLongPressEnd,
                      child: IconButton(
                        icon: Icon(
                          _isComposing ? Icons.send : Icons.mic,
                          color: _isComposing
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.secondary,
                        ),
                        onPressed: _isComposing ? _handleSendText : null,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Build the reply indicator
  Widget _buildReplyIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 8.0,
      ),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          const Icon(
            Icons.reply,
            size: 16.0,
            color: Colors.grey,
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.replyToMessage!.senderName ?? 'User',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12.0,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  widget.replyToMessage!.isDeleted
                      ? 'This message was deleted'
                      : _getReplyPreview(widget.replyToMessage!),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16.0),
            onPressed: widget.onCancelReply,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  /// Get a preview of the reply message content
  String _getReplyPreview(ChatMessage message) {
    if (message.isTextMessage) {
      return message.content;
    } else if (message.isImageMessage) {
      return '📷 Photo';
    } else if (message.isVideoMessage) {
      return '🎥 Video';
    } else if (message.isAudioMessage) {
      return '🎵 Voice Message';
    } else if (message.isLocationMessage) {
      return '📍 Location';
    } else if (message.isLiveLocationMessage) {
      return '📍 Live Location';
    } else {
      return 'Message';
    }
  }

  /// Build the recording UI
  Widget _buildRecordingUI() {
    return AudioRecorderWidget(
      pulseId: widget.pulseId,
      onRecordingComplete: (File recordedFile) {
        setState(() {
          _isRecording = false;
        });
        widget.onSendAudio(recordedFile, _textController.text.trim());
        _textController.clear();
      },
      onRecordingCancelled: () {
        setState(() {
          _isRecording = false;
        });
      },
    );
  }
}

/// Enum for image source
enum ImageSource {
  camera,
  gallery,
}
