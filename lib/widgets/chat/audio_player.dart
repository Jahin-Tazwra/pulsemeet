import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pulsemeet/models/chat_message.dart';
import 'package:pulsemeet/services/audio_service.dart';

/// A widget for playing audio messages
class AudioPlayerWidget extends StatefulWidget {
  final MediaData mediaData;
  final String messageId;
  final bool isFromCurrentUser;

  const AudioPlayerWidget({
    super.key,
    required this.mediaData,
    required this.messageId,
    required this.isFromCurrentUser,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioService _audioService = AudioService();

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;
  double _progress = 0.0;
  String _timeText = '0:00';

  @override
  void initState() {
    super.initState();
    _subscribeToPlaybackUpdates();

    // Set initial time text
    _timeText = widget.mediaData.getFormattedDuration();
  }

  @override
  void dispose() {
    // Stop playback if this widget is disposed while playing
    if (_isPlaying) {
      _audioService.stopAudio();
    }
    super.dispose();
  }

  /// Subscribe to playback updates
  void _subscribeToPlaybackUpdates() {
    _audioService.playbackStateStream.listen((state) {
      if (state.messageId == widget.messageId) {
        setState(() {
          _isPlaying = state.isPlaying;
          _isLoading = state.isLoading;
          _hasError = state.error != null;
          _errorMessage = state.error;
          _progress = state.progress;

          if (state.isPlaying) {
            // Format time as MM:SS
            final int seconds = (state.position / 1000).round();
            final int minutes = seconds ~/ 60;
            final int remainingSeconds = seconds % 60;
            _timeText =
                '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
          } else if (!_isLoading && !_hasError) {
            // Reset to total duration when stopped (but not when loading or error)
            _timeText = widget.mediaData.getFormattedDuration();
            _progress = 0.0;
          }
        });
      }
    });
  }

  /// Toggle playback
  void _togglePlayback() {
    if (_isPlaying) {
      _audioService.stopAudio();
      return;
    }

    // Get the effective URL (local or remote)
    final String effectiveUrl = widget.mediaData.getEffectiveUrl();
    final bool isLocalFile = effectiveUrl.startsWith('file://');

    // For local files, check if the file exists
    if (isLocalFile) {
      final String localPath = effectiveUrl.replaceFirst('file://', '');

      // Check if the file exists
      if (File(localPath).existsSync()) {
        _audioService.playAudio(widget.messageId, localPath, isLocalFile: true);
      } else {
        // Show an error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Audio file not found. It may still be uploading or was deleted.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } else {
      // For remote files, use the normal playback
      _audioService.playAudio(widget.messageId, effectiveUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = widget.isFromCurrentUser
        ? Colors.white
        : Theme.of(context).colorScheme.primary;

    final Color backgroundColor = widget.isFromCurrentUser
        ? Colors.white.withAlpha(51) // Equivalent to opacity 0.2
        : Colors.grey.withAlpha(26); // Equivalent to opacity 0.1

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      width: 240,
      child: Row(
        children: [
          // Play/Pause/Loading/Error button
          _buildControlButton(primaryColor),

          const SizedBox(width: 8),

          // Progress and duration
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Waveform/progress bar
                Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _hasError
                        ? _buildErrorIndicator(primaryColor)
                        : _isLoading
                            ? _buildLoadingIndicator(primaryColor)
                            : Stack(
                                children: [
                                  // Background waveform (static)
                                  _buildWaveform(
                                      context,
                                      1.0,
                                      Colors.grey.withAlpha(
                                          77)), // Equivalent to opacity 0.3

                                  // Progress waveform (animated)
                                  _buildWaveform(
                                      context, _progress, primaryColor),
                                ],
                              ),
                  ),
                ),

                const SizedBox(height: 4),

                // Duration text or error message
                Text(
                  _hasError
                      ? (_errorMessage ?? 'Error loading audio')
                      : _timeText,
                  style: TextStyle(
                    fontSize: 12,
                    color: _hasError
                        ? Colors.red
                        : widget.isFromCurrentUser
                            ? Colors.white70
                            : Colors.black54,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the control button (play/pause/loading/error)
  Widget _buildControlButton(Color primaryColor) {
    if (_isLoading) {
      // Show loading spinner
      return SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(
          color: primaryColor,
          strokeWidth: 2,
        ),
      );
    } else if (_hasError) {
      // Show error icon
      return IconButton(
        icon: const Icon(
          Icons.error_outline,
          color: Colors.red,
          size: 36,
        ),
        onPressed: () {
          // Show error message
          if (mounted && _errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_errorMessage!),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
        padding: EdgeInsets.zero,
      );
    } else {
      // Show play/pause button
      return IconButton(
        icon: Icon(
          _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
          color: primaryColor,
          size: 36,
        ),
        onPressed: _togglePlayback,
        padding: EdgeInsets.zero,
      );
    }
  }

  /// Build a loading indicator
  Widget _buildLoadingIndicator(Color primaryColor) {
    return Center(
      child: LinearProgressIndicator(
        color: primaryColor,
        backgroundColor: Colors.grey.withAlpha(77),
      ),
    );
  }

  /// Build an error indicator
  Widget _buildErrorIndicator(Color primaryColor) {
    return const Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 16,
          ),
          SizedBox(width: 4),
          Text(
            'Error loading audio',
            style: TextStyle(
              color: Colors.red,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Build a waveform visualization
  Widget _buildWaveform(BuildContext context, double fillAmount, Color color) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;

        // Create a simple waveform visualization
        return SizedBox(
          width: width * fillAmount,
          height: height,
          child: CustomPaint(
            painter: WaveformPainter(color: color),
          ),
        );
      },
    );
  }
}

/// Custom painter for drawing a waveform
class WaveformPainter extends CustomPainter {
  final Color color;

  WaveformPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final double width = size.width;
    final double height = size.height;
    const double barWidth = 3;
    const double spacing = 2;
    final int barCount = (width / (barWidth + spacing)).floor();

    // Draw bars with varying heights to simulate a waveform
    for (int i = 0; i < barCount; i++) {
      // Generate a pseudo-random height based on position
      final double normalizedHeight = 0.2 + 0.6 * ((i % 7) / 7);
      final double barHeight = height * normalizedHeight;

      final double left = i * (barWidth + spacing);
      final double top = (height - barHeight) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, barHeight),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
