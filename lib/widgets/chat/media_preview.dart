import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pulsemeet/models/chat_message.dart';
import 'package:pulsemeet/screens/media/media_viewer_screen.dart';

/// A widget that displays a preview of media content (image or video)
class MediaPreview extends StatelessWidget {
  final MediaData mediaData;
  final bool isFromCurrentUser;
  final double maxWidth;
  final double maxHeight;

  const MediaPreview({
    super.key,
    required this.mediaData,
    required this.isFromCurrentUser,
    this.maxWidth = 240.0,
    this.maxHeight = 320.0,
  });

  @override
  Widget build(BuildContext context) {
    // Determine if this is an image or video
    final bool isImage = mediaData.isImage;
    final bool isVideo = mediaData.isVideo;

    // Calculate aspect ratio if dimensions are available
    double aspectRatio = 1.0;
    if (mediaData.width != null &&
        mediaData.height != null &&
        mediaData.height! > 0) {
      aspectRatio = mediaData.width! / mediaData.height!;
    }

    // Calculate dimensions
    double width = maxWidth;
    double height = width / aspectRatio;

    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspectRatio;
    }

    return GestureDetector(
      onTap: () => _openMediaViewer(context),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16.0),
            topRight: Radius.circular(16.0),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Media preview
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16.0),
                topRight: Radius.circular(16.0),
              ),
              child: _buildMediaPreview(isImage, isVideo),
            ),

            // Video indicator
            if (isVideo)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(24.0),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 32.0,
                  ),
                ),
              ),

            // Duration indicator for videos
            if (isVideo && mediaData.duration != null)
              Positioned(
                bottom: 8.0,
                right: 8.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6.0,
                    vertical: 2.0,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    _formatDuration(mediaData.duration!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.0,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build the media preview based on type
  Widget _buildMediaPreview(bool isImage, bool isVideo) {
    // Check if this is a local file (during sending phase)
    final bool isLocalFile = mediaData.url.startsWith('file://');

    if (isImage) {
      if (isLocalFile) {
        // Display local image file
        final String localPath = mediaData.url.replaceFirst('file://', '');
        return Image.file(
          File(localPath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white70, size: 48.0),
          ),
        );
      } else {
        // Display remote image
        return CachedNetworkImage(
          imageUrl: mediaData.url,
          fit: BoxFit.cover,
          placeholder: (context, url) => const Center(
            child: CircularProgressIndicator(),
          ),
          errorWidget: (context, url, error) => const Center(
            child: Icon(Icons.error),
          ),
        );
      }
    } else if (isVideo) {
      if (isLocalFile) {
        // For local videos, we don't generate thumbnails yet, so show a placeholder
        // We'll use the file path later when we implement local video thumbnails
        return Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: Colors.black26,
              child: const Center(
                child: Icon(
                  Icons.video_file,
                  size: 48.0,
                  color: Colors.white70,
                ),
              ),
            ),
            // Add an uploading indicator
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 60.0),
                child: Text(
                  "Uploading...",
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        );
      } else {
        // For remote videos, show the thumbnail if available
        if (mediaData.thumbnailUrl != null) {
          return CachedNetworkImage(
            imageUrl: mediaData.thumbnailUrl!,
            fit: BoxFit.cover,
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator(),
            ),
            errorWidget: (context, url, error) => const Center(
              child: Icon(Icons.video_file),
            ),
          );
        } else {
          // Fallback to a video icon
          return Container(
            color: Colors.black12,
            child: const Center(
              child: Icon(
                Icons.video_file,
                size: 48.0,
                color: Colors.white70,
              ),
            ),
          );
        }
      }
    } else if (mediaData.isAudio) {
      // For audio files, show an audio icon
      return Container(
        color: Colors.black12,
        child: const Center(
          child: Icon(
            Icons.audiotrack,
            size: 48.0,
            color: Colors.white70,
          ),
        ),
      );
    } else {
      // Unsupported media type
      return Container(
        color: Colors.black12,
        child: const Center(
          child: Icon(
            Icons.help,
            size: 48.0,
            color: Colors.white70,
          ),
        ),
      );
    }
  }

  /// Open the media viewer screen
  void _openMediaViewer(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MediaViewerScreen(mediaData: mediaData),
      ),
    );
  }

  /// Format duration in seconds to MM:SS
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
