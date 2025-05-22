import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/models/chat_message.dart';
import 'package:pulsemeet/models/formatted_text.dart';
import 'package:pulsemeet/services/profile_service.dart';
import 'package:pulsemeet/screens/profile/user_profile_screen.dart';
import 'package:pulsemeet/widgets/chat/media_preview.dart';
import 'package:pulsemeet/widgets/chat/location_preview.dart';
import 'package:pulsemeet/widgets/chat/formatted_text_widget.dart';
import 'package:pulsemeet/widgets/chat/audio_player.dart';

/// A widget that displays the content of a chat message
class MessageContent extends StatefulWidget {
  final ChatMessage message;
  final bool isFromCurrentUser;

  const MessageContent({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
  });

  @override
  State<MessageContent> createState() => _MessageContentState();
}

class _MessageContentState extends State<MessageContent> {
  /// Handle mention tap - navigate to user profile
  Future<void> _handleMentionTap(String username) async {
    try {
      final profileService = ProfileService();

      // Search for the user by username
      final profiles = await profileService.searchProfiles(username);

      if (profiles.isNotEmpty) {
        // Find exact match or first result
        final profile = profiles.firstWhere(
          (p) => p.username?.toLowerCase() == username.toLowerCase(),
          orElse: () => profiles.first,
        );

        // Navigate to user profile
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UserProfileScreen(userId: profile.id),
            ),
          );
        }
      } else {
        // Show error if user not found
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('User @$username not found')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error handling mention tap: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading user profile')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // If the message is deleted, show a placeholder
    if (widget.message.isDeleted) {
      return _buildDeletedMessage(context);
    }

    // If the message has expired, show a placeholder
    if (widget.message.isExpired()) {
      return _buildExpiredMessage(context);
    }

    // Handle different message types
    if (widget.message.isTextMessage) {
      return _buildTextMessage(context);
    } else if (widget.message.isImageMessage) {
      return _buildImageMessage(context);
    } else if (widget.message.isVideoMessage) {
      return _buildVideoMessage(context);
    } else if (widget.message.isAudioMessage) {
      return _buildAudioMessage(context);
    } else if (widget.message.isLocationMessage) {
      return _buildLocationMessage(context);
    } else if (widget.message.isLiveLocationMessage) {
      return _buildLiveLocationMessage(context);
    } else {
      return _buildUnsupportedMessage(context);
    }
  }

  /// Build a deleted message placeholder
  Widget _buildDeletedMessage(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      child: Text(
        'This message was deleted',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          fontSize: 14.0,
          color: widget.isFromCurrentUser ? Colors.white70 : Colors.black54,
        ),
        textAlign: TextAlign.left,
      ),
    );
  }

  /// Build an expired message placeholder
  Widget _buildExpiredMessage(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      child: Text(
        'This message has expired',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          fontSize: 14.0,
          color: widget.isFromCurrentUser ? Colors.white70 : Colors.black54,
        ),
        textAlign: TextAlign.left,
      ),
    );
  }

  /// Build a text message
  Widget _buildTextMessage(BuildContext context) {
    // Check if the message has formatted text or mentions
    final formattedText = widget.message.getFormattedText();
    if (formattedText != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12.0),
        child: FormattedTextWidget(
          formattedText: formattedText,
          style: TextStyle(
            color: widget.isFromCurrentUser ? Colors.white : Colors.black87,
            fontSize: 16.0,
          ),
          textAlign:
              widget.isFromCurrentUser ? TextAlign.right : TextAlign.left,
          onMentionTap: (username) {
            // Handle mention tap - navigate to user profile
            _handleMentionTap(username);
          },
        ),
      );
    }

    // Regular text message
    return Container(
      width: double.infinity, // Take full width of parent
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      alignment: widget.isFromCurrentUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Text(
        widget.message.content,
        style: TextStyle(
          color: widget.isFromCurrentUser ? Colors.white : Colors.black87,
          fontSize: 15.0,
        ),
        textAlign: widget.isFromCurrentUser ? TextAlign.right : TextAlign.left,
        softWrap: true,
      ),
    );
  }

  /// Build an image message
  Widget _buildImageMessage(BuildContext context) {
    if (widget.message.mediaData == null) {
      return _buildUnsupportedMessage(context);
    }

    return SizedBox(
      width: double.infinity, // Take full width of parent
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center, // Center the media content
        children: [
          // Image preview
          MediaPreview(
            mediaData: widget.message.mediaData!,
            isFromCurrentUser: widget.isFromCurrentUser,
          ),

          // Caption (if any)
          if (widget.message.content.isNotEmpty)
            Container(
              width: double.infinity, // Full width for caption
              padding: const EdgeInsets.all(12.0),
              child: _buildCaption(context),
            ),
        ],
      ),
    );
  }

  /// Build a video message
  Widget _buildVideoMessage(BuildContext context) {
    if (widget.message.mediaData == null) {
      return _buildUnsupportedMessage(context);
    }

    return SizedBox(
      width: double.infinity, // Take full width of parent
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center, // Center the media content
        children: [
          // Video preview
          MediaPreview(
            mediaData: widget.message.mediaData!,
            isFromCurrentUser: widget.isFromCurrentUser,
          ),

          // Caption (if any)
          if (widget.message.content.isNotEmpty)
            Container(
              width: double.infinity, // Full width for caption
              padding: const EdgeInsets.all(12.0),
              child: Text(
                widget.message.content,
                style: TextStyle(
                  color:
                      widget.isFromCurrentUser ? Colors.white : Colors.black87,
                  fontSize: 14.0,
                ),
                textAlign: TextAlign.left,
              ),
            ),
        ],
      ),
    );
  }

  /// Build an audio message
  Widget _buildAudioMessage(BuildContext context) {
    if (widget.message.mediaData == null) {
      return _buildUnsupportedMessage(context);
    }

    return SizedBox(
      width: double.infinity, // Take full width of parent
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center, // Center the audio player
        children: [
          // Audio player
          AudioPlayerWidget(
            mediaData: widget.message.mediaData!,
            messageId: widget.message.id,
            isFromCurrentUser: widget.isFromCurrentUser,
          ),

          // Caption (if any)
          if (widget.message.content.isNotEmpty)
            Container(
              width: double.infinity, // Full width for caption
              padding: const EdgeInsets.all(12.0),
              child: _buildCaption(context),
            ),
        ],
      ),
    );
  }

  /// Build a location message
  Widget _buildLocationMessage(BuildContext context) {
    if (widget.message.locationData == null) {
      return _buildUnsupportedMessage(context);
    }

    return SizedBox(
      width: double.infinity, // Take full width of parent
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center, // Center the location preview
        children: [
          // Location preview
          LocationPreview(
            location: LatLng(
              widget.message.locationData!.latitude,
              widget.message.locationData!.longitude,
            ),
            address: widget.message.locationData!.address,
            isLive: false,
            isFromCurrentUser: widget.isFromCurrentUser,
          ),

          // Caption (if any)
          if (widget.message.content.isNotEmpty)
            Container(
              width: double.infinity, // Full width for caption
              padding: const EdgeInsets.all(12.0),
              child: _buildCaption(context),
            ),
        ],
      ),
    );
  }

  /// Build a live location message
  Widget _buildLiveLocationMessage(BuildContext context) {
    if (widget.message.locationData == null) {
      return _buildUnsupportedMessage(context);
    }

    // Check if the live location has expired
    final bool isExpired = widget.message.locationData!.expiresAt != null &&
        DateTime.now().isAfter(widget.message.locationData!.expiresAt!);

    return SizedBox(
      width: double.infinity, // Take full width of parent
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center, // Center the location preview
        children: [
          // Location preview
          LocationPreview(
            location: LatLng(
              widget.message.locationData!.latitude,
              widget.message.locationData!.longitude,
            ),
            address: widget.message.locationData!.address,
            isLive: !isExpired,
            expiresAt: widget.message.locationData!.expiresAt,
            isFromCurrentUser: widget.isFromCurrentUser,
          ),

          // Caption (if any)
          if (widget.message.content.isNotEmpty)
            Container(
              width: double.infinity, // Full width for caption
              padding: const EdgeInsets.all(12.0),
              child: _buildCaption(context),
            ),
        ],
      ),
    );
  }

  /// Build an unsupported message placeholder
  Widget _buildUnsupportedMessage(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      child: Text(
        'Unsupported message type',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          fontSize: 14.0,
          color: widget.isFromCurrentUser ? Colors.white70 : Colors.black54,
        ),
        textAlign: TextAlign.left,
      ),
    );
  }

  /// Build a caption with support for mentions
  Widget _buildCaption(BuildContext context) {
    // Check if the caption has mentions
    final formattedText = FormattedText.fromString(widget.message.content);
    if (formattedText.segments
        .any((s) => s.type == FormattedSegmentType.mention)) {
      return FormattedTextWidget(
        formattedText: formattedText,
        style: TextStyle(
          color: widget.isFromCurrentUser ? Colors.white : Colors.black87,
          fontSize: 14.0,
        ),
        textAlign: TextAlign.left,
        onMentionTap: (username) {
          // Handle mention tap
          _handleMentionTap(username);
        },
      );
    }

    // Regular caption
    return Text(
      widget.message.content,
      style: TextStyle(
        color: widget.isFromCurrentUser ? Colors.white : Colors.black87,
        fontSize: 14.0,
      ),
      textAlign: TextAlign.left,
    );
  }
}
