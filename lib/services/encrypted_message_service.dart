import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/models/direct_message.dart';
import 'package:pulsemeet/models/encryption_key.dart';
import 'package:pulsemeet/services/encryption_service.dart';
import 'package:pulsemeet/services/key_management_service.dart';

/// Service for handling encrypted message operations
class EncryptedMessageService {
  static final EncryptedMessageService _instance =
      EncryptedMessageService._internal();
  factory EncryptedMessageService() => _instance;
  EncryptedMessageService._internal();

  final _encryptionService = EncryptionService();
  final _keyManagementService = KeyManagementService();
  final _uuid = const Uuid();

  /// Initialize the service
  Future<void> initialize() async {
    await _encryptionService.initialize();
    await _keyManagementService.initialize();
    debugPrint('EncryptedMessageService initialized');
  }

  /// Check if we can encrypt messages for a specific user
  Future<bool> _canEncryptForUser(String userId) async {
    try {
      // Check if the other user has a public key
      final otherUserPublicKey =
          await _keyManagementService.getUserPublicKey(userId);
      if (otherUserPublicKey == null) {
        debugPrint('User $userId does not have a public key - cannot encrypt');
        return false;
      }

      // Check if we have our own key pair
      if (!_keyManagementService.hasKeyPair) {
        debugPrint('Current user does not have a key pair - cannot encrypt');
        return false;
      }

      debugPrint('Encryption is possible for user $userId');
      return true;
    } catch (e) {
      debugPrint('Error checking encryption capability for user $userId: $e');
      return false;
    }
  }

  /// Encrypt a direct message before sending
  Future<DirectMessage> encryptDirectMessage(
    DirectMessage message,
    String otherUserId,
  ) async {
    try {
      debugPrint('Attempting to encrypt direct message for user: $otherUserId');

      // Check if both users have encryption enabled
      final canEncrypt = await _canEncryptForUser(otherUserId);
      if (!canEncrypt) {
        debugPrint(
            'Cannot encrypt for user $otherUserId - missing public key or encryption not enabled');
        return message; // Return unencrypted message as fallback
      }

      // Get or create conversation key
      final conversationKey =
          await _keyManagementService.getOrCreateDirectMessageKey(otherUserId);
      if (conversationKey == null) {
        debugPrint('Failed to get conversation key for direct message');
        return message; // Return unencrypted message as fallback
      }

      debugPrint(
          'Got conversation key ${conversationKey.keyId} for encryption');

      // Encrypt the message content
      final encryptedContent =
          await _encryptMessageContent(message, conversationKey);
      if (encryptedContent == null) {
        debugPrint('Failed to encrypt direct message content');
        return message; // Return unencrypted message as fallback
      }

      debugPrint('Successfully encrypted direct message');

      // Return encrypted message
      return message.copyWith(
        content: encryptedContent.content,
        isEncrypted: true,
        encryptionMetadata: encryptedContent.metadata,
        keyVersion: conversationKey.version,
      );
    } catch (e) {
      debugPrint('Error encrypting direct message: $e');
      return message; // Return unencrypted message as fallback
    }
  }

  /// Decrypt a direct message after receiving
  Future<DirectMessage> decryptDirectMessage(
    DirectMessage message,
    String otherUserId,
  ) async {
    if (!message.isEncrypted) {
      debugPrint('Message ${message.id} is not encrypted, returning as-is');
      return message; // Already decrypted
    }

    debugPrint(
        'Attempting to decrypt direct message ${message.id} from user $otherUserId');

    try {
      // Get conversation key
      final conversationKey =
          await _keyManagementService.getOrCreateDirectMessageKey(otherUserId);
      if (conversationKey == null) {
        debugPrint(
            'Failed to get conversation key for direct message decryption');
        return message.copyWith(content: '[Decryption failed: No key]');
      }

      debugPrint(
          'Got conversation key ${conversationKey.keyId} for decryption');

      // Decrypt the message content
      final decryptedContent =
          await _decryptMessageContent(message.content, conversationKey);
      if (decryptedContent == null) {
        debugPrint('Failed to decrypt direct message content');
        return message.copyWith(content: '[Decryption failed]');
      }

      debugPrint(
          'Successfully decrypted message ${message.id}: ${decryptedContent.length > 20 ? decryptedContent.substring(0, 20) + '...' : decryptedContent}');

      // Return decrypted message
      return message.copyWith(
        content: decryptedContent,
        isEncrypted: false, // Mark as decrypted for UI
      );
    } catch (e) {
      debugPrint('Error decrypting direct message ${message.id}: $e');
      return message.copyWith(content: '[Decryption failed: $e]');
    }
  }

  /// Encrypt a chat message before sending
  Future<Message> encryptChatMessage(
    Message message,
  ) async {
    try {
      // Get or create conversation key for pulse
      final conversationKey = await _keyManagementService
          .getOrCreatePulseChatKey(message.conversationId);
      if (conversationKey == null) {
        debugPrint('Failed to get conversation key for chat message');
        return message; // Return unencrypted message as fallback
      }

      // Encrypt the message content
      final encryptedContent =
          await _encryptMessageContent(message, conversationKey);
      if (encryptedContent == null) {
        debugPrint('Failed to encrypt chat message content');
        return message; // Return unencrypted message as fallback
      }

      // Return encrypted message
      return message.copyWith(
        content: encryptedContent.content,
        isEncrypted: true,
        encryptionMetadata: encryptedContent.metadata,
        keyVersion: conversationKey.version,
      );
    } catch (e) {
      debugPrint('Error encrypting chat message: $e');
      return message; // Return unencrypted message as fallback
    }
  }

  /// Decrypt a chat message after receiving
  Future<Message> decryptChatMessage(Message message) async {
    if (!message.isEncrypted) {
      return message; // Already decrypted
    }

    debugPrint(
        '🔓 Attempting to decrypt chat message ${message.id} from conversation ${message.conversationId}');
    debugPrint(
        '🔓 Message sender: ${message.senderId}, key version: ${message.keyVersion}');

    try {
      // Get conversation key for pulse
      final conversationKey = await _keyManagementService
          .getOrCreatePulseChatKey(message.conversationId);
      if (conversationKey == null) {
        debugPrint(
            '🔓 ❌ Failed to get conversation key for chat message decryption');
        return message.copyWith(content: '[Decryption failed: No key]');
      }

      debugPrint(
          '🔓 Got conversation key ${conversationKey.keyId} for conversation ${message.conversationId}');

      // Decrypt the message content
      final decryptedContent =
          await _decryptMessageContent(message.content, conversationKey);
      if (decryptedContent == null) {
        debugPrint('🔓 ❌ Failed to decrypt chat message content');
        return message.copyWith(content: '[Decryption failed]');
      }

      debugPrint('🔓 ✅ Successfully decrypted chat message ${message.id}');

      // Return decrypted message
      return message.copyWith(
        content: decryptedContent,
        isEncrypted: false, // Mark as decrypted for UI
      );
    } catch (e) {
      debugPrint('🔓 ❌ Error decrypting chat message ${message.id}: $e');
      return message.copyWith(content: '[Decryption failed: $e]');
    }
  }

  /// Encrypt message content and media
  Future<EncryptedMessageContent?> _encryptMessageContent(
    dynamic message, // DirectMessage or Message
    ConversationKey conversationKey,
  ) async {
    try {
      Map<String, dynamic> contentToEncrypt = {};

      // Encrypt text content
      if (message.content.isNotEmpty) {
        contentToEncrypt['text'] = message.content;
      }

      // Encrypt media data if present
      if (message.mediaData != null) {
        contentToEncrypt['media'] = message.mediaData!.toJson();
      }

      // Encrypt location data if present
      if (message.locationData != null) {
        contentToEncrypt['location'] = message.locationData!.toJson();
      }

      // Add message type and formatting info
      contentToEncrypt['type'] = message.messageType;
      contentToEncrypt['formatted'] = message.isFormatted;

      // Convert to JSON and encrypt
      final jsonContent = jsonEncode(contentToEncrypt);
      final encryptedContent = await _encryptionService.encryptMessage(
        jsonContent,
        conversationKey,
      );

      return EncryptedMessageContent(
        content: encryptedContent,
        metadata: {
          'key_id': conversationKey.keyId,
          'algorithm': 'aes-256-gcm',
          'version': conversationKey.version,
        },
      );
    } catch (e) {
      debugPrint('Error encrypting message content: $e');
      return null;
    }
  }

  /// Decrypt message content
  Future<String?> _decryptMessageContent(
    String encryptedContent,
    ConversationKey conversationKey,
  ) async {
    try {
      // Decrypt the content
      final decryptedJson = await _encryptionService.decryptMessage(
        encryptedContent,
        conversationKey,
      );

      // Parse the decrypted JSON
      final contentMap = jsonDecode(decryptedJson) as Map<String, dynamic>;

      // Extract text content (this is what we display in the UI)
      return contentMap['text'] as String? ?? '';
    } catch (e) {
      debugPrint('Error decrypting message content: $e');
      return null;
    }
  }

  /// Encrypt media file data
  Future<Uint8List?> encryptMediaData(
    Uint8List mediaData,
    ConversationKey conversationKey,
  ) async {
    try {
      final encryptedData = await _encryptionService.encryptData(
        mediaData,
        conversationKey,
      );

      // Combine metadata and ciphertext
      final combined = {
        'metadata': encryptedData.metadata.toJson(),
        'data': base64Encode(encryptedData.ciphertext),
      };

      return Uint8List.fromList(utf8.encode(jsonEncode(combined)));
    } catch (e) {
      debugPrint('Error encrypting media data: $e');
      return null;
    }
  }

  /// Decrypt media file data
  Future<Uint8List?> decryptMediaData(
    Uint8List encryptedMediaData,
    ConversationKey conversationKey,
  ) async {
    try {
      // Parse the combined data
      final combinedJson = jsonDecode(utf8.decode(encryptedMediaData));
      final metadata = EncryptionMetadata.fromJson(combinedJson['metadata']);
      final ciphertext = base64Decode(combinedJson['data']);

      final encryptedData = EncryptedData(
        ciphertext: ciphertext,
        metadata: metadata,
      );

      return await _encryptionService.decryptData(
          encryptedData, conversationKey);
    } catch (e) {
      debugPrint('Error decrypting media data: $e');
      return null;
    }
  }

  /// Check if encryption is available for a conversation
  Future<bool> isEncryptionAvailable(
      String conversationId, ConversationType type) async {
    try {
      ConversationKey? key;

      if (type == ConversationType.direct) {
        // Extract other user ID from conversation ID
        final parts = conversationId.split('_');
        if (parts.length >= 3) {
          // For direct messages, we need to determine the other user ID
          // This is a simplified approach - in production, you'd want a more robust method
          final otherUserId = parts.length > 2 ? parts[2] : parts[1];
          key = await _keyManagementService
              .getOrCreateDirectMessageKey(otherUserId);
        }
      } else {
        key =
            await _keyManagementService.getOrCreatePulseChatKey(conversationId);
      }

      return key != null;
    } catch (e) {
      debugPrint('Error checking encryption availability: $e');
      return false;
    }
  }

  /// Get encryption status for UI display
  Future<EncryptionStatus> getEncryptionStatus(
      String conversationId, ConversationType type) async {
    final isAvailable = await isEncryptionAvailable(conversationId, type);

    if (!isAvailable) {
      return EncryptionStatus.unavailable;
    }

    // For now, assume encryption is always enabled when available
    // In the future, this could be user-configurable
    return EncryptionStatus.enabled;
  }

  /// Encrypt a media file for upload
  Future<File?> encryptMediaFile(
    File mediaFile,
    String conversationId,
    ConversationType conversationType,
  ) async {
    try {
      debugPrint('Encrypting media file: ${mediaFile.path}');

      // Get conversation key
      ConversationKey? conversationKey;
      if (conversationType == ConversationType.direct) {
        // Extract other user ID from conversation ID (format: dm_currentUserId_otherUserId)
        final parts = conversationId.split('_');
        if (parts.length >= 3) {
          final otherUserId = parts[2];
          conversationKey = await _keyManagementService
              .getOrCreateDirectMessageKey(otherUserId);
        }
      } else {
        conversationKey =
            await _keyManagementService.getOrCreatePulseChatKey(conversationId);
      }

      if (conversationKey == null) {
        debugPrint('Failed to get conversation key for media encryption');
        return null;
      }

      // Read file data
      final mediaData = await mediaFile.readAsBytes();

      // Encrypt the data
      final encryptedData = await encryptMediaData(mediaData, conversationKey);
      if (encryptedData == null) {
        debugPrint('Failed to encrypt media data');
        return null;
      }

      // Create encrypted file
      final tempDir = await getTemporaryDirectory();
      final encryptedFileName =
          '${_uuid.v4()}_encrypted${path.extension(mediaFile.path)}';
      final encryptedFile = File('${tempDir.path}/$encryptedFileName');
      await encryptedFile.writeAsBytes(encryptedData);

      debugPrint('Media file encrypted successfully');
      return encryptedFile;
    } catch (e) {
      debugPrint('Error encrypting media file: $e');
      return null;
    }
  }

  /// Decrypt a media file for display
  Future<File?> decryptMediaFile(
    File encryptedFile,
    String conversationId,
    ConversationType conversationType,
  ) async {
    try {
      debugPrint('🔓 Decrypting media file: ${encryptedFile.path}');

      // Verify encrypted file exists and is not empty
      if (!await encryptedFile.exists()) {
        debugPrint('❌ Encrypted file does not exist: ${encryptedFile.path}');
        return null;
      }

      final encryptedFileSize = await encryptedFile.length();
      if (encryptedFileSize == 0) {
        debugPrint('❌ Encrypted file is empty: ${encryptedFile.path}');
        return null;
      }

      debugPrint('📊 Encrypted file size: $encryptedFileSize bytes');

      // Get conversation key
      ConversationKey? conversationKey;
      if (conversationType == ConversationType.direct) {
        // Extract other user ID from conversation ID
        final parts = conversationId.split('_');
        if (parts.length >= 3) {
          final otherUserId = parts[2];
          conversationKey = await _keyManagementService
              .getOrCreateDirectMessageKey(otherUserId);
        }
      } else {
        conversationKey =
            await _keyManagementService.getOrCreatePulseChatKey(conversationId);
      }

      if (conversationKey == null) {
        debugPrint('❌ Failed to get conversation key for media decryption');
        return null;
      }

      debugPrint('🔑 Using conversation key: ${conversationKey.keyId}');

      // Read encrypted data
      final encryptedData = await encryptedFile.readAsBytes();
      debugPrint('📖 Read encrypted data: ${encryptedData.length} bytes');

      // Decrypt the data
      final decryptedData =
          await decryptMediaData(encryptedData, conversationKey);
      if (decryptedData == null) {
        debugPrint('❌ Failed to decrypt media data');
        return null;
      }

      debugPrint('✅ Decrypted data size: ${decryptedData.length} bytes');

      // Create decrypted file with proper extension
      final tempDir = await getTemporaryDirectory();
      final originalExtension = path.extension(encryptedFile.path);
      // Remove '_encrypted' from extension if present
      final cleanExtension = originalExtension.replaceAll('_encrypted', '');
      final decryptedFileName = '${_uuid.v4()}_decrypted$cleanExtension';
      final decryptedFile = File('${tempDir.path}/$decryptedFileName');

      await decryptedFile.writeAsBytes(decryptedData);

      // Verify decrypted file was written correctly
      if (!await decryptedFile.exists()) {
        debugPrint('❌ Failed to write decrypted file');
        return null;
      }

      final decryptedFileSize = await decryptedFile.length();
      if (decryptedFileSize == 0) {
        debugPrint('❌ Decrypted file is empty');
        await decryptedFile.delete();
        return null;
      }

      debugPrint(
          '✅ Media file decrypted successfully: ${decryptedFile.path} ($decryptedFileSize bytes)');
      return decryptedFile;
    } catch (e) {
      debugPrint('❌ Error decrypting media file: $e');
      return null;
    }
  }
}

/// Represents encrypted message content with metadata
class EncryptedMessageContent {
  final String content;
  final Map<String, dynamic> metadata;

  EncryptedMessageContent({
    required this.content,
    required this.metadata,
  });
}

/// Encryption status for UI display
enum EncryptionStatus {
  unavailable,
  disabled,
  enabled,
}
