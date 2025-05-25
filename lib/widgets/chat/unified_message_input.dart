import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/widgets/chat/mention_suggestions.dart';

/// Unified message input component with rich text, media, and voice support
class UnifiedMessageInput extends StatefulWidget {
  final Conversation conversation;
  final Function(String) onSendText;
  final Function(String, {String? caption}) onSendImage;
  final Function(bool) onTypingChanged;

  const UnifiedMessageInput({
    super.key,
    required this.conversation,
    required this.onSendText,
    required this.onSendImage,
    required this.onTypingChanged,
  });

  @override
  State<UnifiedMessageInput> createState() => _UnifiedMessageInputState();
}

class _UnifiedMessageInputState extends State<UnifiedMessageInput> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isTyping = false;
  bool _showMentionSuggestions = false;
  bool _isSending = false;
  String _mentionQuery = '';
  int _mentionStartIndex = -1;
  Timer? _typingTimer;
  DateTime? _lastTypingUpdate;

  List<Profile> _mentionSuggestions = [];

  @override
  void initState() {
    super.initState();
    _setupTextController();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  /// Setup text controller listeners
  void _setupTextController() {
    _textController.addListener(() {
      final text = _textController.text;
      final selection = _textController.selection;

      // Handle typing status
      _handleTypingStatus(text.isNotEmpty);

      // Handle mentions
      _handleMentions(text, selection);

      // Trigger rebuild to update send button state
      setState(() {
        // This will cause the build method to run again and update the send button
      });
    });
  }

  /// Handle typing status with debouncing
  void _handleTypingStatus(bool hasText) {
    _typingTimer?.cancel();

    final now = DateTime.now();
    final timeSinceLastUpdate = _lastTypingUpdate != null
        ? now.difference(_lastTypingUpdate!).inMilliseconds
        : 1000;

    // Debounce typing updates to reduce server calls
    if (hasText != _isTyping && timeSinceLastUpdate > 500) {
      _isTyping = hasText;
      _lastTypingUpdate = now;
      widget.onTypingChanged(hasText);
    }

    // Clear typing status after 3 seconds of inactivity
    if (hasText) {
      _typingTimer = Timer(const Duration(seconds: 3), () {
        if (_isTyping) {
          _isTyping = false;
          _lastTypingUpdate = DateTime.now();
          widget.onTypingChanged(false);
        }
      });
    }
  }

  /// Handle mention detection and suggestions
  void _handleMentions(String text, TextSelection selection) {
    if (selection.baseOffset == -1) return;

    final cursorPosition = selection.baseOffset;

    // Find @ symbol before cursor
    int atIndex = -1;
    for (int i = cursorPosition - 1; i >= 0; i--) {
      if (text[i] == '@') {
        atIndex = i;
        break;
      } else if (text[i] == ' ' || text[i] == '\n') {
        break;
      }
    }

    if (atIndex != -1) {
      // Extract mention query
      final query = text.substring(atIndex + 1, cursorPosition);

      if (query.length <= 20 && !query.contains(' ')) {
        setState(() {
          _showMentionSuggestions = true;
          _mentionQuery = query;
          _mentionStartIndex = atIndex;
        });
        _loadMentionSuggestions(query);
        return;
      }
    }

    // Hide suggestions if no valid mention
    if (_showMentionSuggestions) {
      setState(() {
        _showMentionSuggestions = false;
        _mentionQuery = '';
        _mentionStartIndex = -1;
      });
    }
  }

  /// Load mention suggestions
  Future<void> _loadMentionSuggestions(String query) async {
    try {
      // TODO: Implement mention suggestions loading
      // For now, use empty list
      setState(() {
        _mentionSuggestions = [];
      });
    } catch (e) {
      debugPrint('❌ Error loading mention suggestions: $e');
    }
  }

  /// Handle mention selection
  void _selectMention(Profile user) {
    final text = _textController.text;
    final beforeMention = text.substring(0, _mentionStartIndex);
    final afterMention = text.substring(_textController.selection.baseOffset);

    final username = user.username ?? 'user';
    final newText = '$beforeMention@$username $afterMention';
    final newCursorPosition = beforeMention.length + username.length + 2;

    _textController.text = newText;
    _textController.selection =
        TextSelection.collapsed(offset: newCursorPosition);

    setState(() {
      _showMentionSuggestions = false;
      _mentionQuery = '';
      _mentionStartIndex = -1;
    });
  }

  /// Send text message
  Future<void> _sendTextMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      await widget.onSendText(text);
      _textController.clear();

      // Clear typing status
      _isTyping = false;
      widget.onTypingChanged(false);
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  /// Pick and send image
  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (pickedFile != null) {
        await widget.onSendImage(pickedFile.path);
      }
    } catch (e) {
      debugPrint('❌ Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Show media picker options
  void _showMediaPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Send Media',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMediaOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendImage(ImageSource.camera);
                  },
                ),
                _buildMediaOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendImage(ImageSource.gallery);
                  },
                ),
                _buildMediaOption(
                  icon: Icons.videocam,
                  label: 'Video',
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(context);
                    _pickVideo();
                  },
                ),
                _buildMediaOption(
                  icon: Icons.location_on,
                  label: 'Location',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.pop(context);
                    _sendLocation();
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Build media option button
  Widget _buildMediaOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Pick and send video
  Future<void> _pickVideo() async {
    // TODO: Implement video picking
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Video sending coming soon!')),
    );
  }

  /// Send current location
  Future<void> _sendLocation() async {
    // TODO: Implement location sharing
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Location sharing coming soon!')),
    );
  }

  /// Start voice recording
  Future<void> _startVoiceRecording() async {
    // TODO: Implement voice recording
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice messages coming soon!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Mention suggestions
        if (_showMentionSuggestions)
          MentionSuggestions(
            suggestions: _mentionSuggestions,
            query: _mentionQuery,
            onMentionSelected: _selectMention,
          ),

        // Input area
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF212121) : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            child: Row(
              children: [
                // Attachment button
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _showMediaPicker,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),

                // Text input
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2C2C2C)
                          : const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Send/Voice button
                _buildSendButton(isDark),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Build send button (changes based on input state)
  Widget _buildSendButton(bool isDark) {
    final hasText = _textController.text.trim().isNotEmpty;

    if (_isSending) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    }

    if (hasText) {
      // Send button
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isSending ? null : _sendTextMessage,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.send,
              color: Colors.white,
              size: 20,
              semanticLabel: 'Send message',
            ),
          ),
        ),
      );
    } else {
      // Voice button
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _startVoiceRecording,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[700] : Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mic,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
              size: 20,
              semanticLabel: 'Record voice message',
            ),
          ),
        ),
      );
    }
  }
}
