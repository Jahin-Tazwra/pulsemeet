import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/models/chat_message.dart';
import 'package:pulsemeet/models/formatted_text.dart';
import 'package:pulsemeet/widgets/chat/media_preview.dart';
import 'package:pulsemeet/widgets/chat/location_preview.dart';
import 'package:pulsemeet/widgets/chat/formatted_text_widget.dart';
import 'package:pulsemeet/widgets/chat/audio_player.dart';

/// A widget that displays the content of a chat message
class MessageContent extends StatelessWidget {
  final ChatMessage message;
  final bool isFromCurrentUser;

  const MessageContent({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    // If the message is deleted, show a placeholder
    if (message.isDeleted) {
      return _buildDeletedMessage(context);
    }

    // If the message has expired, show a placeholder
    if (message.isExpired()) {
      return _buildExpiredMessage(context);
    }

    // Handle different message types
    if (message.isTextMessage) {
      return _buildTextMessage(context);
    } else if (message.isImageMessage) {
      return _buildImageMessage(context);
    } else if (message.isVideoMessage) {
      return _buildVideoMessage(context);
    } else if (message.isAudioMessage) {
      return _buildAudioMessage(context);
    } else if (message.isLocationMessage) {
      return _buildLocationMessage(context);
    } else if (message.isLiveLocationMessage) {
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
          color: isFromCurrentUser ? Colors.white70 : Colors.black54,
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
          color: isFromCurrentUser ? Colors.white70 : Colors.black54,
        ),
        textAlign: TextAlign.left,
      ),
    );
  }

  /// Build a text message
  Widget _buildTextMessage(BuildContext context) {
    // Check if the message has formatted text or mentions
    final formattedText = message.getFormattedText();
    if (formattedText != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12.0),
        child: FormattedTextWidget(
          formattedText: formattedText,
          style: TextStyle(
            color: isFromCurrentUser ? Colors.white : Colors.black87,
            fontSize: 16.0,
          ),
          textAlign: isFromCurrentUser ? TextAlign.right : TextAlign.left,
          onMentionTap: (username) {
            // Handle mention tap
            debugPrint('Mention tapped: $username');
            // TODO: Show user profile or handle mention tap
          },
        ),
      );
    }

    // Regular text message
    return Container(
      width: double.infinity, // Take full width of parent
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      alignment:
          isFromCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        message.content,
        style: TextStyle(
          color: isFromCurrentUser ? Colors.white : Colors.black87,
          fontSize: 15.0,
        ),
        textAlign: isFromCurrentUser ? TextAlign.right : TextAlign.left,
        softWrap: true,
      ),
    );
  }

  /// Build an image message
  Widget _buildImageMessage(BuildContext context) {
    if (message.mediaData == null) {
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
            mediaData: message.mediaData!,
            isFromCurrentUser: isFromCurrentUser,
          ),

          // Caption (if any)
          if (message.content.isNotEmpty)
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
    if (message.mediaData == null) {
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
            mediaData: message.mediaData!,
            isFromCurrentUser: isFromCurrentUser,
          ),

          // Caption (if any)
          if (message.content.isNotEmpty)
            Container(
              width: double.infinity, // Full width for caption
              padding: const EdgeInsets.all(12.0),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isFromCurrentUser ? Colors.white : Colors.black87,
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
    if (message.mediaData == null) {
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
            mediaData: message.mediaData!,
            messageId: message.id,
            isFromCurrentUser: isFromCurrentUser,
          ),

          // Caption (if any)
          if (message.content.isNotEmpty)
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
    if (message.locationData == null) {
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
              message.locationData!.latitude,
              message.locationData!.longitude,
            ),
            address: message.locationData!.address,
            isLive: false,
            isFromCurrentUser: isFromCurrentUser,
          ),

          // Caption (if any)
          if (message.content.isNotEmpty)
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
    if (message.locationData == null) {
      return _buildUnsupportedMessage(context);
    }

    // Check if the live location has expired
    final bool isExpired = message.locationData!.expiresAt != null &&
        DateTime.now().isAfter(message.locationData!.expiresAt!);

    return SizedBox(
      width: double.infinity, // Take full width of parent
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center, // Center the location preview
        children: [
          // Location preview
          LocationPreview(
            location: LatLng(
              message.locationData!.latitude,
              message.locationData!.longitude,
            ),
            address: message.locationData!.address,
            isLive: !isExpired,
            expiresAt: message.locationData!.expiresAt,
            isFromCurrentUser: isFromCurrentUser,
          ),

          // Caption (if any)
          if (message.content.isNotEmpty)
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
          color: isFromCurrentUser ? Colors.white70 : Colors.black54,
        ),
        textAlign: TextAlign.left,
      ),
    );
  }

  /// Build a caption with support for mentions
  Widget _buildCaption(BuildContext context) {
    // Check if the caption has mentions
    final formattedText = FormattedText.fromString(message.content);
    if (formattedText.segments
        .any((s) => s.type == FormattedSegmentType.mention)) {
      return FormattedTextWidget(
        formattedText: formattedText,
        style: TextStyle(
          color: isFromCurrentUser ? Colors.white : Colors.black87,
          fontSize: 14.0,
        ),
        textAlign: TextAlign.left,
        onMentionTap: (username) {
          // Handle mention tap
          debugPrint('Mention tapped in caption: $username');
          // TODO: Show user profile or handle mention tap
        },
      );
    }

    // Regular caption
    return Text(
      message.content,
      style: TextStyle(
        color: isFromCurrentUser ? Colors.white : Colors.black87,
        fontSize: 14.0,
      ),
      textAlign: TextAlign.left,
    );
  }
}
