import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pulsemeet/services/audio_service.dart';

/// A widget for recording audio with visual feedback
class AudioRecorderWidget extends StatefulWidget {
  final Function(File) onRecordingComplete;
  final Function() onRecordingCancelled;
  final String pulseId;

  const AudioRecorderWidget({
    super.key,
    required this.onRecordingComplete,
    required this.onRecordingCancelled,
    required this.pulseId,
  });

  @override
  State<AudioRecorderWidget> createState() => _AudioRecorderWidgetState();
}

class _AudioRecorderWidgetState extends State<AudioRecorderWidget>
    with SingleTickerProviderStateMixin {
  final AudioService _audioService = AudioService();
  bool _isRecording = false;
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;
  int _recordingDuration = 0;
  double _amplitude = 0.0;

  // Animation controller for the recording indicator
  late AnimationController _animationController;

  // Timer for updating the recording duration
  Timer? _durationTimer;

  // Subscription to recording state updates
  StreamSubscription? _recordingSubscription;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Subscribe to recording state updates
    _subscribeToRecordingUpdates();

    // Start recording automatically
    _startRecording();
  }

  @override
  void dispose() {
    // Cancel animation controller
    _animationController.dispose();

    // Cancel timer
    _durationTimer?.cancel();

    // Cancel subscription
    _recordingSubscription?.cancel();

    // Stop recording if still active
    if (_isRecording) {
      _audioService.cancelRecording();
    }

    super.dispose();
  }

  /// Subscribe to recording state updates
  void _subscribeToRecordingUpdates() {
    _recordingSubscription = _audioService.recordingStateStream.listen((state) {
      setState(() {
        _isRecording = state.isRecording;
        _isLoading = state.isLoading;
        _hasError = state.error != null;
        _errorMessage = state.error;
        _recordingDuration = state.duration;
        _amplitude = state.amplitude;
      });
    });
  }

  /// Start recording
  Future<void> _startRecording() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    final success = await _audioService.startRecording();

    if (success) {
      setState(() {
        _isRecording = true;
        _isLoading = false;
      });

      // Start a timer to update the recording duration
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingDuration++;
        });
      });
    } else {
      setState(() {
        _isRecording = false;
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Failed to start recording';
      });
    }
  }

  /// Stop recording and complete
  Future<void> _stopRecording() async {
    setState(() {
      _isLoading = true;
    });

    // Cancel the duration timer
    _durationTimer?.cancel();
    _durationTimer = null;

    // Stop recording
    final recordedFile = await _audioService.stopRecording();

    if (recordedFile != null) {
      widget.onRecordingComplete(recordedFile);
    } else {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Failed to save recording';
      });
    }
  }

  /// Cancel recording
  void _cancelRecording() {
    // Cancel the duration timer
    _durationTimer?.cancel();
    _durationTimer = null;

    // Cancel recording
    _audioService.cancelRecording();

    // Notify parent
    widget.onRecordingCancelled();
  }

  /// Format duration as MM:SS
  String _formatDuration(int seconds) {
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24.0),
      ),
      child: _hasError ? _buildErrorState() : _buildRecordingState(),
    );
  }

  /// Build the recording state UI
  Widget _buildRecordingState() {
    return Row(
      children: [
        // Recording indicator
        _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            : AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withAlpha(
                          (76 + 179 * _animationController.value)
                              .toInt()), // 0.3-1.0 opacity
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.mic,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  );
                },
              ),

        const SizedBox(width: 12),

        // Waveform visualization
        Expanded(
          child: SizedBox(
            height: 40,
            child: _buildWaveform(),
          ),
        ),

        const SizedBox(width: 12),

        // Duration
        Text(
          _formatDuration(_recordingDuration),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(width: 12),

        // Stop button
        IconButton(
          icon: const Icon(Icons.stop_circle_outlined),
          onPressed: _stopRecording,
          color: Theme.of(context).colorScheme.primary,
        ),

        // Cancel button
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: _cancelRecording,
          color: Theme.of(context).colorScheme.error,
        ),
      ],
    );
  }

  /// Build the error state UI
  Widget _buildErrorState() {
    return Row(
      children: [
        const Icon(
          Icons.error_outline,
          color: Colors.red,
        ),

        const SizedBox(width: 12),

        // Error message
        Expanded(
          child: Text(
            _errorMessage ?? 'Error recording audio',
            style: const TextStyle(
              color: Colors.red,
            ),
          ),
        ),

        // Retry button
        TextButton(
          onPressed: _startRecording,
          child: const Text('Retry'),
        ),

        // Cancel button
        TextButton(
          onPressed: _cancelRecording,
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  /// Build a waveform visualization based on amplitude
  Widget _buildWaveform() {
    return CustomPaint(
      painter: WaveformPainter(
        amplitude: _amplitude,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// Custom painter for drawing a waveform
class WaveformPainter extends CustomPainter {
  final double amplitude;
  final Color color;

  WaveformPainter({
    required this.amplitude,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path();

    // Calculate the center line
    final centerY = size.height / 2;

    // Calculate the number of points to draw
    const pointSpacing = 5.0;
    final numPoints = (size.width / pointSpacing).floor();

    // Start at the left edge
    path.moveTo(0, centerY);

    // Draw the waveform
    for (int i = 0; i < numPoints; i++) {
      final x = i * pointSpacing;
      final normalizedAmplitude = amplitude.clamp(0.0, 1.0);
      final maxDeviation = size.height * 0.4 * normalizedAmplitude;

      // Use a sine wave with varying amplitude
      final y = centerY + sin(i * 0.5) * maxDeviation;

      path.lineTo(x, y);
    }

    // Draw the path
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.amplitude != amplitude || oldDelegate.color != color;
  }
}
