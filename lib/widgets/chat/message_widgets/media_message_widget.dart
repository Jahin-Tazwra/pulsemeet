import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/models/message.dart';

/// Widget for displaying media messages (images, videos, audio)
class MediaMessageWidget extends StatelessWidget {
  final Message message;
  final Conversation conversation;
  final bool isFromCurrentUser;

  const MediaMessageWidget({
    super.key,
    required this.message,
    required this.conversation,
    required this.isFromCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    if (message.mediaData == null) {
      return const SizedBox.shrink();
    }

    switch (message.messageType) {
      case MessageType.image:
        return _buildImageWidget(context);
      case MessageType.video:
        return _buildVideoWidget(context);
      case MessageType.audio:
        return _buildAudioWidget(context);
      default:
        return const SizedBox.shrink();
    }
  }

  /// Build image widget
  Widget _buildImageWidget(BuildContext context) {
    final mediaData = message.mediaData!;
    
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 250,
        maxHeight: 300,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: mediaData.url,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 200,
                height: 150,
                color: Colors.grey[300],
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                width: 200,
                height: 150,
                color: Colors.grey[300],
                child: const Center(
                  child: Icon(Icons.error),
                ),
              ),
            ),
          ),
          
          // Caption (if any)
          if (message.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isFromCurrentUser ? Colors.white : Colors.black87,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build video widget
  Widget _buildVideoWidget(BuildContext context) {
    final mediaData = message.mediaData!;
    
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 250,
        maxHeight: 300,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Video thumbnail with play button
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: mediaData.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: mediaData.thumbnailUrl!,
                        fit: BoxFit.cover,
                        width: 200,
                        height: 150,
                        placeholder: (context, url) => Container(
                          width: 200,
                          height: 150,
                          color: Colors.grey[300],
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 200,
                          height: 150,
                          color: Colors.grey[300],
                          child: const Center(
                            child: Icon(Icons.video_library),
                          ),
                        ),
                      )
                    : Container(
                        width: 200,
                        height: 150,
                        color: Colors.grey[300],
                        child: const Center(
                          child: Icon(Icons.video_library, size: 48),
                        ),
                      ),
              ),
              
              // Play button overlay
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          // Video info
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.videocam,
                      size: 16,
                      color: isFromCurrentUser ? Colors.white70 : Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      mediaData.duration != null 
                          ? _formatDuration(mediaData.duration!)
                          : 'Video',
                      style: TextStyle(
                        color: isFromCurrentUser ? Colors.white70 : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      mediaData.formattedSize,
                      style: TextStyle(
                        color: isFromCurrentUser ? Colors.white70 : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                
                // Caption (if any)
                if (message.content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    message.content,
                    style: TextStyle(
                      color: isFromCurrentUser ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build audio widget
  Widget _buildAudioWidget(BuildContext context) {
    final mediaData = message.mediaData!;
    
    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Audio player controls
          Row(
            children: [
              // Play/pause button
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isFromCurrentUser ? Colors.white.withOpacity(0.2) : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow,
                  color: isFromCurrentUser ? Colors.white : Colors.black87,
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Waveform placeholder and duration
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Waveform placeholder
                    Container(
                      height: 20,
                      decoration: BoxDecoration(
                        color: isFromCurrentUser ? Colors.white.withOpacity(0.2) : Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: List.generate(20, (index) {
                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              height: (index % 3 + 1) * 6.0,
                              decoration: BoxDecoration(
                                color: isFromCurrentUser ? Colors.white : Colors.grey[600],
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    
                    const SizedBox(height: 4),
                    
                    // Duration and size
                    Row(
                      children: [
                        Text(
                          mediaData.duration != null 
                              ? _formatDuration(mediaData.duration!)
                              : '0:00',
                          style: TextStyle(
                            color: isFromCurrentUser ? Colors.white70 : Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          mediaData.formattedSize,
                          style: TextStyle(
                            color: isFromCurrentUser ? Colors.white70 : Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // Caption (if any)
          if (message.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message.content,
              style: TextStyle(
                color: isFromCurrentUser ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Format duration in seconds to MM:SS
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
