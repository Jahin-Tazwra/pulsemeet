import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:audio_session/audio_session.dart';

/// A service for handling audio recording and playback
class AudioService {
  static final AudioService _instance = AudioService._internal();

  factory AudioService() => _instance;

  AudioService._internal() {
    _initRecorder();
    _initPlayer();
  }

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  final Uuid _uuid = const Uuid();
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isRecorderInitialized = false;
  bool _isPlayerInitialized = false;
  String? _recordingPath;
  StreamSubscription? _recorderSubscription;
  StreamSubscription? _playerSubscription;

  // Recording state
  bool _isRecording = false;
  int _recordingDuration = 0;
  final StreamController<RecordingState> _recordingStateController =
      StreamController<RecordingState>.broadcast();

  // Playback state
  String? _currentlyPlayingId;
  final StreamController<PlaybackState> _playbackStateController =
      StreamController<PlaybackState>.broadcast();

  // Getters
  bool get isRecording => _isRecording;
  int get recordingDuration => _recordingDuration;
  Stream<RecordingState> get recordingStateStream =>
      _recordingStateController.stream;
  Stream<PlaybackState> get playbackStateStream =>
      _playbackStateController.stream;

  /// Initialize the recorder
  Future<void> _initRecorder() async {
    try {
      // Check if recorder is already initialized
      if (_isRecorderInitialized) {
        return;
      }

      // Request permission before initializing
      final hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        debugPrint('Microphone permission not granted');
        // Notify about permission issue
        _recordingStateController.add(RecordingState(
          isRecording: false,
          duration: 0,
          amplitude: 0,
          error: 'Microphone permission not granted',
        ));
        return;
      }

      // Initialize recorder with session
      await _recorder.openRecorder();

      // Configure audio session for recording
      await _configureAudioSession();

      _isRecorderInitialized = true;
      debugPrint('Recorder initialized successfully');
    } catch (e) {
      debugPrint('Error initializing recorder: $e');
      // Notify about initialization error
      _recordingStateController.add(RecordingState(
        isRecording: false,
        duration: 0,
        amplitude: 0,
        error: 'Failed to initialize recorder: $e',
      ));
    }
  }

  /// Initialize the player
  Future<void> _initPlayer() async {
    try {
      // Check if player is already initialized
      if (_isPlayerInitialized) {
        return;
      }

      // Initialize player
      await _player.openPlayer();

      // Configure audio session for playback if not already configured
      if (!_isRecorderInitialized) {
        await _configureAudioSession();
      }

      _isPlayerInitialized = true;
      debugPrint('Player initialized successfully');
    } catch (e) {
      debugPrint('Error initializing player: $e');
    }
  }

  /// Configure audio session
  Future<void> _configureAudioSession() async {
    try {
      // Configure audio session for optimal recording and playback
      // This helps with audio routing and handling interruptions
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

      debugPrint('Audio session configured successfully');
    } catch (e) {
      debugPrint('Error configuring audio session: $e');
    }
  }

  /// Request microphone permission
  Future<bool> requestMicrophonePermission() async {
    // First check if permission is already granted
    var status = await Permission.microphone.status;

    if (status.isGranted) {
      return true;
    }

    // If permission is denied but not permanently, request it
    if (status.isDenied) {
      status = await Permission.microphone.request();
      return status.isGranted;
    }

    // If permission is permanently denied, open app settings
    if (status.isPermanentlyDenied) {
      debugPrint('Microphone permission permanently denied, opening settings');
      await openAppSettings();
    }

    return false;
  }

  /// Start recording
  Future<bool> startRecording() async {
    // Notify that we're starting the recording process
    _recordingStateController.add(RecordingState(
      isRecording: false,
      duration: 0,
      amplitude: 0,
      isLoading: true,
    ));

    if (!_isRecorderInitialized) {
      await _initRecorder();

      // Check if initialization failed
      if (!_isRecorderInitialized) {
        debugPrint('Failed to initialize recorder');
        _recordingStateController.add(RecordingState(
          isRecording: false,
          duration: 0,
          amplitude: 0,
          error: 'Failed to initialize audio recorder',
          isLoading: false,
        ));
        return false;
      }
    }

    // Check permission
    final hasPermission = await requestMicrophonePermission();
    if (!hasPermission) {
      debugPrint('Microphone permission not granted');
      _recordingStateController.add(RecordingState(
        isRecording: false,
        duration: 0,
        amplitude: 0,
        error: 'Microphone permission not granted',
        isLoading: false,
      ));
      return false;
    }

    try {
      // Create a temporary file for recording
      final tempDir = await getTemporaryDirectory();
      _recordingPath = '${tempDir.path}/${_uuid.v4()}.m4a';

      debugPrint('Recording to: $_recordingPath');

      // Activate audio session
      final session = await AudioSession.instance;
      await session.setActive(true);

      // Start recording
      await _recorder.startRecorder(
        toFile: _recordingPath,
        codec: Codec.aacMP4,
        audioSource: AudioSource.microphone,
      );

      _isRecording = true;
      _recordingDuration = 0;

      // Notify that recording has started
      _recordingStateController.add(RecordingState(
        isRecording: true,
        duration: 0,
        amplitude: 0,
        isLoading: false,
      ));

      // Listen to recording updates
      _recorderSubscription = _recorder.onProgress?.listen((event) {
        _recordingDuration = event.duration.inSeconds;
        final double amplitude = event.decibels ?? 0;

        debugPrint(
            'Recording progress: ${event.duration.inSeconds}s, amplitude: $amplitude');

        _recordingStateController.add(RecordingState(
          isRecording: true,
          duration: _recordingDuration,
          amplitude: amplitude,
          isLoading: false,
        ));
      });

      debugPrint('Recording started successfully');
      return true;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      _recordingStateController.add(RecordingState(
        isRecording: false,
        duration: 0,
        amplitude: 0,
        error: 'Error starting recording: $e',
        isLoading: false,
      ));
      return false;
    }
  }

  /// Stop recording
  Future<File?> stopRecording() async {
    if (!_isRecording || !_isRecorderInitialized) {
      debugPrint(
          'Cannot stop recording: not recording or recorder not initialized');
      _recordingStateController.add(RecordingState(
        isRecording: false,
        duration: 0,
        amplitude: 0,
        error: 'No active recording to stop',
        isLoading: false,
      ));
      return null;
    }

    // Notify that we're stopping the recording
    _recordingStateController.add(RecordingState(
      isRecording: true,
      duration: _recordingDuration,
      amplitude: 0,
      isLoading: true,
    ));

    try {
      debugPrint('Stopping recording...');

      // Stop recording
      final String? path = await _recorder.stopRecorder();

      // Deactivate audio session
      final session = await AudioSession.instance;
      await session.setActive(false);

      // Cancel subscription
      await _recorderSubscription?.cancel();
      _recorderSubscription = null;

      _isRecording = false;

      // Notify that recording has stopped
      _recordingStateController.add(RecordingState(
        isRecording: false,
        duration: _recordingDuration,
        amplitude: 0,
        isLoading: false,
      ));

      // Return the recorded file
      if (path != null) {
        debugPrint('Recording saved to: $path');
        final file = File(path);
        if (await file.exists()) {
          final fileSize = await file.length();
          debugPrint('File size: $fileSize bytes');

          // Check if the file is valid (not empty)
          if (fileSize > 0) {
            return file;
          } else {
            debugPrint('File is empty: $path');
            _recordingStateController.add(RecordingState(
              isRecording: false,
              duration: 0,
              amplitude: 0,
              error: 'Recorded file is empty',
              isLoading: false,
            ));
          }
        } else {
          debugPrint('File does not exist: $path');
          _recordingStateController.add(RecordingState(
            isRecording: false,
            duration: 0,
            amplitude: 0,
            error: 'Recorded file not found',
            isLoading: false,
          ));
        }
      } else if (_recordingPath != null) {
        debugPrint('Using fallback path: $_recordingPath');
        final file = File(_recordingPath!);
        if (await file.exists()) {
          final fileSize = await file.length();
          debugPrint('File size: $fileSize bytes');

          // Check if the file is valid (not empty)
          if (fileSize > 0) {
            return file;
          } else {
            debugPrint('File is empty: $_recordingPath');
            _recordingStateController.add(RecordingState(
              isRecording: false,
              duration: 0,
              amplitude: 0,
              error: 'Recorded file is empty',
              isLoading: false,
            ));
          }
        } else {
          debugPrint('Fallback file does not exist: $_recordingPath');
          _recordingStateController.add(RecordingState(
            isRecording: false,
            duration: 0,
            amplitude: 0,
            error: 'Recorded file not found',
            isLoading: false,
          ));
        }
      } else {
        debugPrint('No recording path available');
        _recordingStateController.add(RecordingState(
          isRecording: false,
          duration: 0,
          amplitude: 0,
          error: 'No recording path available',
          isLoading: false,
        ));
      }

      return null;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _recordingStateController.add(RecordingState(
        isRecording: false,
        duration: 0,
        amplitude: 0,
        error: 'Error stopping recording: $e',
        isLoading: false,
      ));
      return null;
    }
  }

  /// Cancel recording
  Future<void> cancelRecording() async {
    if (!_isRecording || !_isRecorderInitialized) {
      return;
    }

    try {
      // Stop recording
      await _recorder.stopRecorder();

      // Cancel subscription
      await _recorderSubscription?.cancel();
      _recorderSubscription = null;

      _isRecording = false;
      _recordingStateController.add(RecordingState(
        isRecording: false,
        duration: 0,
        amplitude: 0,
      ));

      // Delete the recorded file
      if (_recordingPath != null) {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('Error canceling recording: $e');
    }
  }

  /// Play audio from a URL or local file
  Future<void> playAudio(String messageId, String url,
      {bool isLocalFile = false}) async {
    // Notify that we're starting to load the audio
    _playbackStateController.add(PlaybackState(
      messageId: messageId,
      isPlaying: false,
      position: 0,
      duration: 0,
      progress: 0.0,
      isLoading: true,
    ));

    if (!_isPlayerInitialized) {
      await _initPlayer();

      // Check if initialization failed
      if (!_isPlayerInitialized) {
        debugPrint('Failed to initialize player');
        _playbackStateController.add(PlaybackState(
          messageId: messageId,
          isPlaying: false,
          position: 0,
          duration: 0,
          progress: 0.0,
          error: 'Failed to initialize audio player',
          isLoading: false,
        ));
        return;
      }
    }

    // Stop any currently playing audio
    if (_player.isPlaying) {
      await stopAudio();
    }

    try {
      debugPrint('Playing audio from URL: $url');
      _currentlyPlayingId = messageId;

      // Activate audio session
      final session = await AudioSession.instance;
      await session.setActive(true);

      // Check if the file exists for local files
      if (isLocalFile) {
        final file = File(url);
        if (!await file.exists()) {
          debugPrint('Local audio file does not exist: $url');
          _playbackStateController.add(PlaybackState(
            messageId: messageId,
            isPlaying: false,
            position: 0,
            duration: 0,
            progress: 0.0,
            error: 'Audio file not found',
            isLoading: false,
          ));
          return;
        }
      }

      // Start playback
      if (isLocalFile) {
        // For local files, use fromURI with file:// prefix
        await _player.startPlayer(
          fromURI: 'file://$url',
          codec: Codec.aacMP4,
          whenFinished: () {
            debugPrint('Audio playback finished');
            _playbackStateController.add(PlaybackState(
              messageId: messageId,
              isPlaying: false,
              position: 0,
              duration: 0,
              progress: 0.0,
              isLoading: false,
            ));
            _currentlyPlayingId = null;

            // Deactivate audio session
            session.setActive(false).then((_) {
              debugPrint('Audio session deactivated');
            }).catchError((e) {
              debugPrint('Error deactivating audio session: $e');
            });
          },
        );
      } else {
        // For remote URLs
        await _player.startPlayer(
          fromURI: url,
          codec: Codec.aacADTS,
          whenFinished: () {
            debugPrint('Audio playback finished');
            _playbackStateController.add(PlaybackState(
              messageId: messageId,
              isPlaying: false,
              position: 0,
              duration: 0,
              progress: 0.0,
              isLoading: false,
            ));
            _currentlyPlayingId = null;

            // Deactivate audio session
            session.setActive(false).then((_) {
              debugPrint('Audio session deactivated');
            }).catchError((e) {
              debugPrint('Error deactivating audio session: $e');
            });
          },
        );
      }

      debugPrint('Audio playback started');

      // Notify that playback has started
      _playbackStateController.add(PlaybackState(
        messageId: messageId,
        isPlaying: true,
        position: 0,
        duration: 0,
        progress: 0.0,
        isLoading: false,
      ));

      // Listen to playback updates
      _playerSubscription = _player.onProgress?.listen((event) {
        final position = event.position.inMilliseconds;
        final duration = event.duration.inMilliseconds;
        final progress = duration > 0 ? (position / duration).toDouble() : 0.0;

        debugPrint('Playback progress: $position/$duration ms ($progress)');

        _playbackStateController.add(PlaybackState(
          messageId: messageId,
          isPlaying: true,
          position: position,
          duration: duration,
          progress: progress,
          isLoading: false,
        ));
      });
    } catch (e) {
      debugPrint('Error playing audio: $e');

      // Reset state in case of error
      _playbackStateController.add(PlaybackState(
        messageId: messageId,
        isPlaying: false,
        position: 0,
        duration: 0,
        progress: 0.0,
        error: 'Error playing audio: $e',
        isLoading: false,
      ));
      _currentlyPlayingId = null;
    }
  }

  /// Stop audio playback
  Future<void> stopAudio() async {
    if (!_isPlayerInitialized || !_player.isPlaying) {
      return;
    }

    try {
      // Stop playback
      await _player.stopPlayer();

      // Cancel subscription
      await _playerSubscription?.cancel();
      _playerSubscription = null;

      if (_currentlyPlayingId != null) {
        _playbackStateController.add(PlaybackState(
          messageId: _currentlyPlayingId!,
          isPlaying: false,
          position: 0,
          duration: 0,
          progress: 0,
        ));
        _currentlyPlayingId = null;
      }
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    }
  }

  /// Upload audio file to Supabase storage
  Future<MediaData?> uploadAudio(File audioFile, String pulseId) async {
    try {
      debugPrint('Uploading audio file: ${audioFile.path}');

      // Check if file exists
      if (!await audioFile.exists()) {
        debugPrint('Audio file does not exist: ${audioFile.path}');
        return null;
      }

      // Check if file is valid (not empty)
      final int fileSize = await audioFile.length();
      debugPrint('Audio file size: $fileSize bytes');

      if (fileSize <= 0) {
        debugPrint('Audio file is empty: ${audioFile.path}');
        return null;
      }

      // Generate unique filename
      final String fileName = '${_uuid.v4()}.m4a';
      final String filePath = 'pulse_$pulseId/$fileName';
      debugPrint('Storage path: $filePath');

      // Upload the file
      // Use audio/aac for M4A files to match Supabase bucket configuration
      final String uploadMimeType =
          audioFile.path.toLowerCase().endsWith('.m4a')
              ? 'audio/aac'
              : 'audio/mpeg';

      try {
        await _supabase.storage.from('audio').upload(
              filePath,
              audioFile,
              fileOptions: FileOptions(
                contentType: uploadMimeType,
                upsert: true,
              ),
            );
        debugPrint(
            'File uploaded successfully with MIME type: $uploadMimeType');
      } catch (uploadError) {
        // Check if the bucket exists
        debugPrint('Upload error: $uploadError');

        // Try to create the bucket if it doesn't exist
        try {
          debugPrint('Checking if bucket exists...');
          final buckets = await _supabase.storage.listBuckets();
          final bucketExists = buckets.any((bucket) => bucket.name == 'audio');

          if (!bucketExists) {
            debugPrint('Audio bucket does not exist, creating...');
            // Note: Creating buckets requires admin privileges
            // This is just for debugging purposes
            return null;
          }
        } catch (e) {
          debugPrint('Error checking buckets: $e');
          return null;
        }

        // Check for specific error types
        if (uploadError.toString().contains('permission')) {
          debugPrint('Permission denied when uploading to storage');
          return null;
        } else if (uploadError.toString().contains('network')) {
          debugPrint('Network error when uploading to storage');
          return null;
        }

        // Rethrow the original error
        rethrow;
      }

      // Get the public URL
      final String fileUrl =
          _supabase.storage.from('audio').getPublicUrl(filePath);
      debugPrint('File URL: $fileUrl');

      // Get duration
      int? duration = _recordingDuration;
      debugPrint('Audio duration: $duration seconds');

      // Create MediaData object with local file path as fallback
      // Use audio/aac for M4A files to match Supabase bucket configuration
      final String mimeType = audioFile.path.toLowerCase().endsWith('.m4a')
          ? 'audio/aac'
          : 'audio/mpeg';

      return MediaData(
        url: fileUrl,
        mimeType: mimeType,
        size: fileSize,
        duration: duration,
      );
    } catch (e) {
      debugPrint('Error uploading audio: $e');

      // Return a MediaData object with just the local file path
      // This allows the UI to still display and play the audio even if upload failed
      try {
        final int fileSize = await audioFile.length();
        // Use audio/aac for M4A files to match Supabase bucket configuration
        final String mimeType = audioFile.path.toLowerCase().endsWith('.m4a')
            ? 'audio/aac'
            : 'audio/mpeg';

        return MediaData(
          url: 'file://${audioFile.path}',
          mimeType: mimeType,
          size: fileSize,
          duration: _recordingDuration,
        );
      } catch (_) {
        return null;
      }
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    // Cancel subscriptions
    await _recorderSubscription?.cancel();
    await _playerSubscription?.cancel();

    // Close recorder and player
    await _recorder.closeRecorder();
    await _player.closePlayer();

    // Close controllers
    await _recordingStateController.close();
    await _playbackStateController.close();
  }
}

/// Model class for recording state
class RecordingState {
  final bool isRecording;
  final int duration;
  final double amplitude;
  final String? error;
  final bool isLoading;

  RecordingState({
    required this.isRecording,
    required this.duration,
    required this.amplitude,
    this.error,
    this.isLoading = false,
  });
}

/// Model class for playback state
class PlaybackState {
  final String messageId;
  final bool isPlaying;
  final int position;
  final int duration;
  final double progress;
  final String? error;
  final bool isLoading;

  PlaybackState({
    required this.messageId,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.progress,
    this.error,
    this.isLoading = false,
  });
}
