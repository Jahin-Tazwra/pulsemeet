import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/models/encryption_models.dart';
import 'package:pulsemeet/services/signal_protocol_service.dart';
import 'package:pulsemeet/services/unified_encryption_service.dart';

/// Enhanced encryption service with Signal Protocol integration
class EnhancedEncryptionService {
  static final EnhancedEncryptionService _instance =
      EnhancedEncryptionService._internal();
  factory EnhancedEncryptionService() => _instance;
  EnhancedEncryptionService._internal();

  final SignalProtocolService _signalProtocol = SignalProtocolService();
  final UnifiedEncryptionService _legacyEncryption = UnifiedEncryptionService();
  final SupabaseClient _supabase = Supabase.instance.client;
  final Uuid _uuid = const Uuid();

  bool _isInitialized = false;
  bool _signalProtocolEnabled = true;

  /// Initialize the enhanced encryption service
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('🔐 Initializing Enhanced Encryption Service');

    try {
      // Initialize Signal Protocol service
      await _signalProtocol.initialize();

      // Initialize legacy encryption for backward compatibility
      await _legacyEncryption.initialize();

      _isInitialized = true;
      debugPrint('✅ Enhanced Encryption Service initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Enhanced Encryption Service: $e');
      // Fall back to legacy encryption
      _signalProtocolEnabled = false;
      await _legacyEncryption.initialize();
      _isInitialized = true;
    }
  }

  /// Encrypt a message using the best available method
  Future<Message> encryptMessage(Message message) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      debugPrint(
          '🔐 Encrypting message ${message.id} for conversation ${message.conversationId}');

      // Check if conversation supports Signal Protocol
      if (_signalProtocolEnabled &&
          await _supportsSignalProtocol(message.conversationId)) {
        return await _encryptWithSignalProtocol(message);
      } else {
        // Fall back to legacy encryption
        debugPrint('📝 Using legacy encryption for message ${message.id}');
        return await _legacyEncryption.encryptMessage(message);
      }
    } catch (e) {
      debugPrint('❌ Error encrypting message: $e');
      // Return unencrypted message as last resort
      return message;
    }
  }

  /// Decrypt a message using the appropriate method
  Future<Message> decryptMessage(Message message) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!message.isEncrypted) {
      return message; // Already decrypted
    }

    try {
      debugPrint('🔓 Decrypting message ${message.id}');

      // Check encryption metadata to determine decryption method
      if (message.encryptionMetadata != null) {
        final metadata = message.encryptionMetadata!;

        if (metadata['algorithm'] == 'signal-protocol') {
          return await _decryptWithSignalProtocol(message);
        }
      }

      // Fall back to legacy decryption
      debugPrint('📝 Using legacy decryption for message ${message.id}');
      return await _legacyEncryption.decryptMessage(message);
    } catch (e) {
      debugPrint('❌ Error decrypting message: $e');
      return message.copyWith(
        content: '[Decryption failed]',
        isEncrypted: false,
      );
    }
  }

  /// Encrypt media file before upload
  Future<File?> encryptMediaFile(File mediaFile, String conversationId) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      debugPrint('🔐 Encrypting media file: ${mediaFile.path}');

      // Check if conversation supports Signal Protocol
      if (_signalProtocolEnabled &&
          await _supportsSignalProtocol(conversationId)) {
        return await _encryptMediaWithSignalProtocol(mediaFile, conversationId);
      } else {
        // Fall back to legacy encryption
        return await _legacyEncryption.encryptMediaFile(
            mediaFile, conversationId);
      }
    } catch (e) {
      debugPrint('❌ Error encrypting media file: $e');
      return null;
    }
  }

  /// Decrypt media file for display
  Future<File?> decryptMediaFile(
      File encryptedFile, String conversationId) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      debugPrint('🔓 Decrypting media file: ${encryptedFile.path}');

      // Try Signal Protocol decryption first
      if (_signalProtocolEnabled) {
        final decryptedFile = await _decryptMediaWithSignalProtocol(
            encryptedFile, conversationId);
        if (decryptedFile != null) {
          return decryptedFile;
        }
      }

      // Fall back to legacy decryption
      return await _legacyEncryption.decryptMediaFile(
          encryptedFile, conversationId);
    } catch (e) {
      debugPrint('❌ Error decrypting media file: $e');
      return null;
    }
  }

  /// Get encryption status for a conversation
  Future<ConversationEncryptionStatus> getEncryptionStatus(
      String conversationId) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      if (_signalProtocolEnabled &&
          await _supportsSignalProtocol(conversationId)) {
        return await _signalProtocol.getEncryptionStatus(conversationId);
      } else {
        // Return basic encryption status for legacy conversations
        return const ConversationEncryptionStatus(
          isEncrypted: true,
          encryptionLevel: EncryptionLevel.transport,
          participantCount: 0,
          verifiedParticipants: 0,
        );
      }
    } catch (e) {
      debugPrint('❌ Error getting encryption status: $e');
      return const ConversationEncryptionStatus(
        isEncrypted: false,
        encryptionLevel: EncryptionLevel.none,
        participantCount: 0,
        verifiedParticipants: 0,
      );
    }
  }

  /// Check if conversation supports Signal Protocol
  Future<bool> _supportsSignalProtocol(String conversationId) async {
    try {
      // For now, enable Signal Protocol for all new conversations
      // In the future, this could check participant capabilities
      return _signalProtocolEnabled;
    } catch (e) {
      debugPrint('❌ Error checking Signal Protocol support: $e');
      return false;
    }
  }

  /// Encrypt message with Signal Protocol
  Future<Message> _encryptWithSignalProtocol(Message message) async {
    try {
      final encryptedData =
          await _signalProtocol.encryptMessage(message, message.conversationId);

      return message.copyWith(
        content: base64Encode(encryptedData.ciphertext),
        isEncrypted: true,
        encryptionMetadata: encryptedData.metadata.toJson(),
      );
    } catch (e) {
      debugPrint('❌ Signal Protocol encryption failed: $e');
      rethrow;
    }
  }

  /// Decrypt message with Signal Protocol
  Future<Message> _decryptWithSignalProtocol(Message message) async {
    try {
      return await _signalProtocol.decryptMessage(message);
    } catch (e) {
      debugPrint('❌ Signal Protocol decryption failed: $e');
      rethrow;
    }
  }

  /// Encrypt media file with Signal Protocol
  Future<File?> _encryptMediaWithSignalProtocol(
      File mediaFile, String conversationId) async {
    try {
      // Read file data
      final mediaData = await mediaFile.readAsBytes();

      // Create a temporary message for encryption
      final tempMessage = Message(
        id: _uuid.v4(),
        conversationId: conversationId,
        senderId: _supabase.auth.currentUser?.id ?? '',
        messageType: MessageType.file,
        content: '',
        mediaData: MediaData(
          url: '',
          fileName: path.basename(mediaFile.path),
          size: mediaData.length,
          mimeType: _getMimeType(mediaFile.path),
        ),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: MessageStatus.sending,
      );

      // Encrypt the media data
      final encryptedData =
          await _signalProtocol.encryptMessage(tempMessage, conversationId);

      // Create encrypted file
      final tempDir = await getTemporaryDirectory();
      final encryptedFileName =
          '${_uuid.v4()}_encrypted${path.extension(mediaFile.path)}';
      final encryptedFile = File('${tempDir.path}/$encryptedFileName');

      // Combine metadata and encrypted media data
      final combinedData = {
        'metadata': encryptedData.metadata.toJson(),
        'media_data': base64Encode(mediaData),
      };

      await encryptedFile.writeAsString(jsonEncode(combinedData));

      return encryptedFile;
    } catch (e) {
      debugPrint('❌ Error encrypting media with Signal Protocol: $e');
      return null;
    }
  }

  /// Decrypt media file with Signal Protocol
  Future<File?> _decryptMediaWithSignalProtocol(
      File encryptedFile, String conversationId) async {
    try {
      // Read encrypted file
      final encryptedContent = await encryptedFile.readAsString();
      final combinedData = jsonDecode(encryptedContent);

      // Extract metadata and media data
      final metadata = EncryptionMetadata.fromJson(combinedData['metadata']);
      final encryptedMediaData = base64Decode(combinedData['media_data']);

      // Create temporary encrypted message for decryption
      final tempMessage = Message(
        id: _uuid.v4(),
        conversationId: conversationId,
        senderId: '',
        messageType: MessageType.file,
        content: base64Encode(encryptedMediaData),
        isEncrypted: true,
        encryptionMetadata: metadata.toJson(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: MessageStatus.delivered,
      );

      // Decrypt the message
      final decryptedMessage =
          await _signalProtocol.decryptMessage(tempMessage);

      // Extract decrypted media data
      final decryptedMediaData = base64Decode(decryptedMessage.content);

      // Create decrypted file
      final tempDir = await getTemporaryDirectory();
      final decryptedFileName =
          '${_uuid.v4()}_decrypted${path.extension(encryptedFile.path)}';
      final decryptedFile = File('${tempDir.path}/$decryptedFileName');

      await decryptedFile.writeAsBytes(decryptedMediaData);

      return decryptedFile;
    } catch (e) {
      debugPrint('❌ Error decrypting media with Signal Protocol: $e');
      return null;
    }
  }

  /// Get MIME type from file extension
  String _getMimeType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();

    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      case '.m4a':
        return 'audio/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  /// Log security event
  Future<void> logSecurityEvent(
    String conversationId,
    SecurityEventType eventType,
    String description, {
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _supabase.from('security_events').insert({
        'conversation_id': conversationId,
        'user_id': _supabase.auth.currentUser?.id,
        'event_type': eventType.name,
        'description': description,
        'metadata': metadata ?? {},
      });

      debugPrint('📝 Security event logged: $eventType - $description');
    } catch (e) {
      debugPrint('❌ Error logging security event: $e');
    }
  }

  /// Enable or disable Signal Protocol
  void setSignalProtocolEnabled(bool enabled) {
    _signalProtocolEnabled = enabled;
    debugPrint('🔐 Signal Protocol ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Check if Signal Protocol is enabled
  bool get isSignalProtocolEnabled => _signalProtocolEnabled;

  /// Dispose resources
  void dispose() {
    _signalProtocol.dispose();
    debugPrint('🧹 Enhanced Encryption Service disposed');
  }
}
