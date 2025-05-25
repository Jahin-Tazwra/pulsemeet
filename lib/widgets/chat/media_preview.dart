import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/models/encryption_key.dart';
import 'package:pulsemeet/screens/media/media_viewer_screen.dart';
import 'package:pulsemeet/services/media_service.dart';

/// A widget that displays a preview of media content (image or video)
class MediaPreview extends StatefulWidget {
  final MediaData mediaData;
  final bool isFromCurrentUser;
  final double maxWidth;
  final double maxHeight;
  final String? conversationId;
  final ConversationType? conversationType;

  const MediaPreview({
    super.key,
    required this.mediaData,
    required this.isFromCurrentUser,
    this.maxWidth = 240.0,
    this.maxHeight = 320.0,
    this.conversationId,
    this.conversationType,
  });

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview>
    with AutomaticKeepAliveClientMixin {
  // Cache the decrypted URL to prevent re-decryption on rebuilds
  String? _cachedDecryptedUrl;
  bool _isDecrypting = false;

  @override
  bool get wantKeepAlive => true; // Keep widget alive to prevent rebuilds

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Determine if this is an image or video
    final bool isImage = widget.mediaData.isImage;
    final bool isVideo = widget.mediaData.isVideo;

    // Calculate aspect ratio if dimensions are available
    double aspectRatio = 1.0;
    if (widget.mediaData.width != null &&
        widget.mediaData.height != null &&
        widget.mediaData.height! > 0) {
      aspectRatio = widget.mediaData.width! / widget.mediaData.height!;
    }

    // Calculate dimensions
    double width = widget.maxWidth;
    double height = width / aspectRatio;

    if (height > widget.maxHeight) {
      height = widget.maxHeight;
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
            if (isVideo && widget.mediaData.duration != null)
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
                    _formatDuration(widget.mediaData.duration!),
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
    final bool isLocalFile = widget.mediaData.url.startsWith('file://');

    if (isImage) {
      if (isLocalFile) {
        // Display local image file
        final String localPath =
            widget.mediaData.url.replaceFirst('file://', '');
        return Image.file(
          File(localPath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white70, size: 48.0),
          ),
        );
      } else {
        // Display remote image with potential decryption
        return _buildEncryptedImageWidget();
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
        if (widget.mediaData.thumbnailUrl != null) {
          return CachedNetworkImage(
            imageUrl: widget.mediaData.thumbnailUrl!,
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
    } else if (widget.mediaData.isAudio) {
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
        builder: (context) => MediaViewerScreen(
          mediaData: widget.mediaData,
          conversationId: widget.conversationId,
          conversationType: widget.conversationType,
        ),
      ),
    );
  }

  /// Build encrypted image widget with decryption and retry mechanism
  Widget _buildEncryptedImageWidget() {
    debugPrint(
        '🖼️ Building encrypted image widget for ${widget.mediaData.url}');

    // If we don't have conversation context, fall back to regular display
    if (widget.conversationId == null || widget.conversationType == null) {
      debugPrint(
          '⚠️ No conversation context, using regular CachedNetworkImage');
      return CachedNetworkImage(
        imageUrl: widget.mediaData.url,
        fit: BoxFit.cover,
        placeholder: (context, url) => const Center(
          child: CircularProgressIndicator(),
        ),
        errorWidget: (context, url, error) => const Center(
          child: Icon(Icons.error),
        ),
      );
    }

    // Use FutureBuilder to handle decryption with retry
    return FutureBuilder<String?>(
      key: ValueKey(
          'decrypt_${widget.mediaData.url}'), // Stable key for FutureBuilder
      future: _getDecryptedUrlWithRetry(),
      builder: (context, snapshot) {
        debugPrint(
            '🔄 FutureBuilder state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, hasError: ${snapshot.hasError}');

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          debugPrint('❌ FutureBuilder error or no data: ${snapshot.error}');
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, color: Colors.white70, size: 48.0),
                SizedBox(height: 8),
                Text(
                  'Failed to decrypt image',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }

        final decryptedUrl = snapshot.data!;
        debugPrint('✅ Using decrypted URL: $decryptedUrl');

        // If it's a local file after decryption, use Image.file
        if (decryptedUrl.startsWith('file://')) {
          final localPath = decryptedUrl.replaceFirst('file://', '');
          return Image.file(
            File(localPath),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('❌ Error displaying decrypted image: $error');
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, color: Colors.white70, size: 48.0),
                    SizedBox(height: 8),
                    Text(
                      'Image display error',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        } else {
          // Use CachedNetworkImage for remote URLs
          return CachedNetworkImage(
            imageUrl: decryptedUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator(),
            ),
            errorWidget: (context, url, error) => const Center(
              child: Icon(Icons.error),
            ),
          );
        }
      },
    );
  }

  /// Get decrypted URL with retry mechanism
  Future<String?> _getDecryptedUrlWithRetry({int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint(
            '🔄 Decryption attempt $attempt/$maxRetries for ${widget.mediaData.url}');

        final decryptedUrl = await _getDecryptedUrl();
        if (decryptedUrl != null) {
          debugPrint('✅ Decryption successful on attempt $attempt');
          return decryptedUrl;
        }

        debugPrint('❌ Decryption failed on attempt $attempt');

        // Wait before retrying (exponential backoff)
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      } catch (e) {
        debugPrint('❌ Decryption error on attempt $attempt: $e');

        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        } else {
          rethrow;
        }
      }
    }

    return null;
  }

  /// Get decrypted URL for media with caching
  Future<String?> _getDecryptedUrl() async {
    // Return cached URL if available
    if (_cachedDecryptedUrl != null) {
      debugPrint('📁 Using cached decrypted URL for ${widget.mediaData.url}');
      return _cachedDecryptedUrl;
    }

    if (widget.conversationId == null || widget.conversationType == null) {
      return widget.mediaData.url;
    }

    if (_isDecrypting) {
      debugPrint(
          '⏳ Decryption already in progress for ${widget.mediaData.url}');
      return null;
    }

    try {
      _isDecrypting = true;
      final mediaService = MediaService();
      final decryptedUrl = await mediaService.getDecryptedMediaUrl(
        widget.mediaData,
        widget.conversationId!,
        widget.conversationType!,
      );

      // Cache the result
      if (decryptedUrl != null) {
        _cachedDecryptedUrl = decryptedUrl;
        debugPrint('💾 Cached decrypted URL for ${widget.mediaData.url}');
      }

      return decryptedUrl ?? widget.mediaData.url;
    } catch (e) {
      debugPrint('Error getting decrypted media URL: $e');
      return widget.mediaData.url; // Fallback to original URL
    } finally {
      _isDecrypting = false;
    }
  }

  /// Format duration in seconds to MM:SS
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
