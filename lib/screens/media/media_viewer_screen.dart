import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/services/media_service.dart';
import 'package:pulsemeet/models/encryption_key.dart';

/// A screen for viewing media (images and videos)
class MediaViewerScreen extends StatefulWidget {
  final MediaData mediaData;
  final String? conversationId;
  final ConversationType? conversationType;

  const MediaViewerScreen({
    super.key,
    required this.mediaData,
    this.conversationId,
    this.conversationType,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  bool _isInitialized = false;
  final MediaService _mediaService = MediaService();
  String? _decryptedUrl;
  bool _isDecrypting = false;

  @override
  void initState() {
    super.initState();

    // Initialize media (decrypt if needed, then initialize video player)
    _initializeMedia();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  /// Initialize media (decrypt if needed, then initialize video player)
  Future<void> _initializeMedia() async {
    setState(() {
      _isDecrypting = true;
    });

    try {
      // Get decrypted URL if this is encrypted media
      if (widget.conversationId != null && widget.conversationType != null) {
        _decryptedUrl = await _mediaService.getDecryptedMediaUrl(
          widget.mediaData,
          widget.conversationId!,
          widget.conversationType!,
        );
      } else {
        _decryptedUrl = widget.mediaData.url;
      }

      // Initialize video player if this is a video
      if (widget.mediaData.isVideo && _decryptedUrl != null) {
        await _initializeVideoPlayer();
      }
    } catch (e) {
      debugPrint('Error initializing media: $e');
      _decryptedUrl = widget.mediaData.url; // Fallback to original URL
    } finally {
      setState(() {
        _isDecrypting = false;
      });
    }
  }

  /// Initialize the video player
  Future<void> _initializeVideoPlayer() async {
    if (_decryptedUrl == null) return;

    // Handle local file URLs
    if (_decryptedUrl!.startsWith('file://')) {
      final localPath = _decryptedUrl!.replaceFirst('file://', '');
      _videoController = VideoPlayerController.file(File(localPath));
    } else {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(_decryptedUrl!),
      );
    }

    await _videoController!.initialize();

    // Add listener for playback state
    _videoController!.addListener(() {
      if (mounted) {
        setState(() {
          _isPlaying = _videoController!.value.isPlaying;
        });
      }
    });

    setState(() {
      _isInitialized = true;
    });
  }

  /// Toggle video playback
  void _togglePlayback() {
    if (_videoController == null) return;

    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withAlpha(128),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: widget.mediaData.isImage
            ? _buildImageViewer()
            : _buildVideoViewer(),
      ),
    );
  }

  /// Build the image viewer
  Widget _buildImageViewer() {
    if (_isDecrypting) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_decryptedUrl == null) {
      return const Center(
        child: Icon(
          Icons.error,
          color: Colors.white,
          size: 48.0,
        ),
      );
    }

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 3.0,
      child: _decryptedUrl!.startsWith('file://')
          ? Image.file(
              File(_decryptedUrl!.replaceFirst('file://', '')),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(
                  Icons.error,
                  color: Colors.white,
                  size: 48.0,
                ),
              ),
            )
          : CachedNetworkImage(
              imageUrl: _decryptedUrl!,
              fit: BoxFit.contain,
              placeholder: (context, url) => const Center(
                child: CircularProgressIndicator(),
              ),
              errorWidget: (context, url, error) => const Center(
                child: Icon(
                  Icons.error,
                  color: Colors.white,
                  size: 48.0,
                ),
              ),
            ),
    );
  }

  /// Build the video viewer
  Widget _buildVideoViewer() {
    if (_isDecrypting || !_isInitialized || _videoController == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // Video player
        AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),

        // Play/pause button
        GestureDetector(
          onTap: _togglePlayback,
          child: Container(
            width: 60.0,
            height: 60.0,
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(128),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 36.0,
            ),
          ),
        ),

        // Video progress indicator
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: VideoProgressIndicator(
            _videoController!,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: Colors.blue,
              bufferedColor: Colors.grey,
              backgroundColor: Colors.black45,
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 16.0,
              horizontal: 16.0,
            ),
          ),
        ),
      ],
    );
  }
}
