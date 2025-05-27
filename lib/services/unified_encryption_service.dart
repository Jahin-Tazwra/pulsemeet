import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/models/encryption_key.dart';
import 'package:pulsemeet/services/encryption_service.dart';
import 'package:pulsemeet/services/key_management_service.dart';
import 'package:pulsemeet/services/encryption_isolate_service.dart';

/// Unified service for handling encrypted message operations with new models
class UnifiedEncryptionService {
  static final UnifiedEncryptionService _instance =
      UnifiedEncryptionService._internal();
  factory UnifiedEncryptionService() => _instance;
  UnifiedEncryptionService._internal();

  final _encryptionService = EncryptionService();
  final _keyManagementService = KeyManagementService();
  final _encryptionIsolateService = EncryptionIsolateService.instance;
  final _uuid = const Uuid();
  final _supabase = Supabase.instance.client;

  /// Initialize the service
  Future<void> initialize() async {
    await _encryptionService.initialize();
    await _keyManagementService.initialize();
    await _encryptionIsolateService.initialize();
    debugPrint('UnifiedEncryptionService initialized');
  }

  /// Encrypt a message before sending - OPTIMIZED FOR PERFORMANCE
  Future<Message> encryptMessage(Message message) async {
    final encryptionStopwatch = Stopwatch()..start();

    try {
      debugPrint('🔐 Attempting to encrypt message ${message.id}');

      // PERFORMANCE OPTIMIZATION 1: Parallel key retrieval and content preparation
      final keyFuture = _getConversationKey(message.conversationId);
      final contentBytes =
          utf8.encode(message.content); // Prepare content in parallel

      final conversationKey = await keyFuture;
      if (conversationKey == null) {
        encryptionStopwatch.stop();
        debugPrint(
            '! Failed to get conversation key for message encryption (${encryptionStopwatch.elapsedMilliseconds}ms)');
        debugPrint('⚠️ Message will be sent unencrypted');
        return message; // Return unencrypted message as fallback
      }

      debugPrint(
          '🔑 Got conversation key ${conversationKey.keyId} for encryption (${encryptionStopwatch.elapsedMilliseconds}ms)');

      // PERFORMANCE OPTIMIZATION 2: Use background isolate for CPU-intensive encryption
      final encryptedContent = await _encryptMessageContentOptimized(
          message, conversationKey, contentBytes);

      if (encryptedContent == null) {
        encryptionStopwatch.stop();
        debugPrint(
            '❌ Failed to encrypt message content (${encryptionStopwatch.elapsedMilliseconds}ms)');
        debugPrint('⚠️ Message will be sent unencrypted');
        return message; // Return unencrypted message as fallback
      }

      encryptionStopwatch.stop();
      debugPrint(
          '🔐 Message encrypted successfully (${encryptionStopwatch.elapsedMilliseconds}ms)');

      // Return encrypted message
      return message.copyWith(
        content: encryptedContent.content,
        isEncrypted: true,
        encryptionMetadata: encryptedContent.metadata,
        keyVersion: conversationKey.version,
      );
    } catch (e) {
      encryptionStopwatch.stop();
      debugPrint(
          '❌ Error encrypting message (${encryptionStopwatch.elapsedMilliseconds}ms): $e');
      return message; // Return unencrypted message as fallback
    }
  }

  /// Decrypt a message after receiving
  Future<Message> decryptMessage(Message message) async {
    if (!message.isEncrypted) {
      debugPrint('📝 Message ${message.id} is not encrypted, returning as-is');
      return message; // Already decrypted
    }

    debugPrint('🔓 Attempting to decrypt message ${message.id}');

    try {
      // Get conversation key
      final conversationKey = await _getConversationKey(message.conversationId);
      if (conversationKey == null) {
        debugPrint('❌ Failed to get conversation key for message decryption');
        return message.copyWith(content: '[Decryption failed: No key]');
      }

      debugPrint(
          '🔑 Got conversation key ${conversationKey.keyId} for decryption');

      // Decrypt the message content
      final decryptedContent =
          await _decryptMessageContent(message.content, conversationKey);
      if (decryptedContent == null) {
        debugPrint('❌ Failed to decrypt message content');
        return message.copyWith(content: '[Decryption failed]');
      }

      debugPrint('✅ Successfully decrypted message ${message.id}');

      // Return decrypted message
      return message.copyWith(
        content: decryptedContent.text,
        mediaData: decryptedContent.mediaData,
        locationData: decryptedContent.locationData,
        isEncrypted: false, // Mark as decrypted for UI
      );
    } catch (e) {
      debugPrint('❌ Error decrypting message ${message.id}: $e');
      return message.copyWith(content: '[Decryption failed: $e]');
    }
  }

  /// Get conversation key based on conversation ID
  Future<ConversationKey?> _getConversationKey(String conversationId) async {
    try {
      debugPrint('🔍 Getting conversation key for: $conversationId');

      // Determine conversation type based on conversation ID or database lookup
      final conversationType = await _determineConversationType(conversationId);
      debugPrint('🔍 Conversation type determined: $conversationType');

      if (conversationType == ConversationType.direct) {
        // Extract other user ID from direct message conversation ID
        final otherUserId =
            await _getOtherUserIdFromConversation(conversationId);
        debugPrint('🔍 Other user ID for DM: $otherUserId');

        if (otherUserId != null) {
          // Pass the actual conversation ID to ensure consistent key generation
          final key = await _keyManagementService.getOrCreateDirectMessageKey(
              otherUserId,
              actualConversationId: conversationId);
          debugPrint('🔍 Direct message key result: ${key?.keyId ?? 'null'}');
          return key;
        } else {
          debugPrint('❌ Could not determine other user ID for direct message');
        }
      } else {
        // For pulse conversations, use the conversation ID as pulse ID
        debugPrint('🔍 Getting pulse chat key for: $conversationId');
        final key =
            await _keyManagementService.getOrCreatePulseChatKey(conversationId);
        debugPrint('🔍 Pulse chat key result: ${key?.keyId ?? 'null'}');
        return key;
      }

      debugPrint('❌ No conversation key could be obtained');
      return null;
    } catch (e) {
      debugPrint('❌ Error getting conversation key: $e');
      return null;
    }
  }

  /// Determine conversation type from conversation ID
  Future<ConversationType> _determineConversationType(
      String conversationId) async {
    try {
      // Check database for conversation type
      final response = await _supabase
          .from('conversations')
          .select('type')
          .eq('id', conversationId)
          .maybeSingle();

      if (response != null && response['type'] == 'direct_message') {
        return ConversationType.direct;
      }

      return ConversationType.pulse;
    } catch (e) {
      debugPrint('❌ Error determining conversation type: $e');
      // Default to pulse type if we can't determine
      return ConversationType.pulse;
    }
  }

  /// Get other user ID from direct message conversation
  Future<String?> _getOtherUserIdFromConversation(String conversationId) async {
    try {
      // Get current user ID from key management service
      final currentUserId = _keyManagementService.currentUserId;
      debugPrint('🔍 Current user ID: $currentUserId');

      if (currentUserId == null) {
        debugPrint('❌ No current user ID available');
        return null;
      }

      // Use the secure database function to get all participants
      final response = await _supabase.rpc(
          'get_conversation_participants_for_user',
          params: {'conversation_id_param': conversationId});

      debugPrint('🔍 Conversation participants: $response');

      if (response != null && response is List && response.isNotEmpty) {
        // Find the other user (not the current user)
        for (final participant in response) {
          final userId = participant['user_id'] as String;
          if (userId != currentUserId) {
            debugPrint('🔍 Found other user ID: $userId');
            return userId;
          }
        }
      }

      debugPrint('❌ No other user found in conversation participants');
      return null;
    } catch (e) {
      debugPrint('❌ Error getting other user ID: $e');
      return null;
    }
  }

  /// OPTIMIZED: Encrypt message content using background isolate for performance
  Future<EncryptedMessageContent?> _encryptMessageContentOptimized(
    Message message,
    ConversationKey conversationKey,
    Uint8List contentBytes,
  ) async {
    final encryptionStopwatch = Stopwatch()..start();

    try {
      // PERFORMANCE OPTIMIZATION: Use background isolate for CPU-intensive encryption
      debugPrint('🔧 Using background isolate for encryption');

      // Prepare content for encryption
      Map<String, dynamic> contentToEncrypt = {};

      // Add text content
      if (message.content.isNotEmpty) {
        contentToEncrypt['text'] = message.content;
      }

      // Add media data if present
      if (message.mediaData != null) {
        contentToEncrypt['media'] = message.mediaData!.toJson();
      }

      // Add location data if present
      if (message.locationData != null) {
        contentToEncrypt['location'] = message.locationData!.toJson();
      }

      // Add call data if present
      if (message.callData != null) {
        contentToEncrypt['call'] = message.callData!.toJson();
      }

      // Add message metadata
      contentToEncrypt['type'] = message.messageType.name;
      contentToEncrypt['formatted'] = message.isFormatted;
      contentToEncrypt['mentions'] = message.mentions;

      // Convert to JSON
      final jsonContent = jsonEncode(contentToEncrypt);

      // Use background isolate for encryption (non-blocking)
      final encryptionResult = await _encryptionIsolateService.encryptMessage(
        content: jsonContent,
        conversationKey: base64Encode(conversationKey.symmetricKey),
      );

      encryptionStopwatch.stop();
      debugPrint(
          '🔧 Background encryption completed (${encryptionStopwatch.elapsedMilliseconds}ms)');

      // COMPATIBILITY FIX: Format the encrypted content to match expected decryption format
      final compatibleEncryptedContent =
          _formatEncryptedContentForCompatibility(
        encryptionResult['encryptedContent'],
        encryptionResult['metadata'],
      );

      return EncryptedMessageContent(
        content: compatibleEncryptedContent,
        metadata: {
          'key_id': conversationKey.keyId,
          'algorithm': 'aes-256-gcm',
          'version': conversationKey.version,
          ...encryptionResult['metadata'],
        },
      );
    } catch (e) {
      encryptionStopwatch.stop();
      debugPrint(
          '❌ Background encryption failed (${encryptionStopwatch.elapsedMilliseconds}ms): $e');

      // FALLBACK: Use synchronous encryption if isolate fails
      debugPrint('🔄 Falling back to synchronous encryption');
      return await _encryptMessageContentFallback(message, conversationKey);
    }
  }

  /// FALLBACK: Synchronous encryption method for when isolate fails
  Future<EncryptedMessageContent?> _encryptMessageContentFallback(
    Message message,
    ConversationKey conversationKey,
  ) async {
    final fallbackStopwatch = Stopwatch()..start();

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

      // Encrypt call data if present
      if (message.callData != null) {
        contentToEncrypt['call'] = message.callData!.toJson();
      }

      // Add message type and formatting info
      contentToEncrypt['type'] = message.messageType.name;
      contentToEncrypt['formatted'] = message.isFormatted;
      contentToEncrypt['mentions'] = message.mentions;

      // Convert to JSON and encrypt using synchronous method
      final jsonContent = jsonEncode(contentToEncrypt);
      final encryptedContent = await _encryptionService.encryptMessage(
        jsonContent,
        conversationKey,
      );

      fallbackStopwatch.stop();
      debugPrint(
          '🔄 Fallback encryption completed (${fallbackStopwatch.elapsedMilliseconds}ms)');

      return EncryptedMessageContent(
        content: encryptedContent,
        metadata: {
          'key_id': conversationKey.keyId,
          'algorithm': 'aes-256-gcm',
          'version': conversationKey.version,
        },
      );
    } catch (e) {
      fallbackStopwatch.stop();
      debugPrint(
          '❌ Fallback encryption failed (${fallbackStopwatch.elapsedMilliseconds}ms): $e');
      return null;
    }
  }

  /// COMPATIBILITY FIX: Format encrypted content to match expected decryption format
  String _formatEncryptedContentForCompatibility(
    String encryptedContent,
    Map<String, dynamic> metadata,
  ) {
    try {
      // Create the combined format that the decryption service expects
      final combined = {
        'metadata': {
          'key_id': metadata['key_id'] ?? '',
          'algorithm': metadata['algorithm'] ?? 'aes-256-gcm',
          'iv': metadata['iv'] ?? '',
          'auth_tag': metadata['auth_tag'] ?? '',
          'version': metadata['version'] ?? 1,
        },
        'ciphertext': encryptedContent,
      };

      // Encode as base64 JSON (format expected by EncryptionService.decryptMessage)
      return base64Encode(utf8.encode(jsonEncode(combined)));
    } catch (e) {
      debugPrint('❌ Error formatting encrypted content for compatibility: $e');
      // Return original content as fallback
      return encryptedContent;
    }
  }

  /// Decrypt message content with enhanced error handling and format compatibility
  Future<DecryptedMessageContent?> _decryptMessageContent(
    String encryptedContent,
    ConversationKey conversationKey,
  ) async {
    final decryptionStopwatch = Stopwatch()..start();

    try {
      debugPrint('🔓 Starting message content decryption');

      // ENHANCED DECRYPTION: Try multiple decryption methods for compatibility
      String decryptedJson;

      try {
        // Method 1: Try standard EncryptionService decryption (for new format)
        decryptedJson = await _encryptionService.decryptMessage(
          encryptedContent,
          conversationKey,
        );
        debugPrint('✅ Standard decryption successful');
      } catch (e) {
        debugPrint(
            '🔄 Standard decryption failed, trying isolate decryption: $e');

        // Method 2: Try isolate decryption (for isolate-encrypted messages)
        try {
          decryptedJson = await _encryptionIsolateService.decryptMessage(
            encryptedContent: encryptedContent,
            conversationKey: base64Encode(conversationKey.symmetricKey),
            encryptionMetadata: {
              'algorithm': 'aes-256-gcm',
              'version': 1,
            },
          );
          debugPrint('✅ Isolate decryption successful');
        } catch (isolateError) {
          debugPrint(
              '❌ Both decryption methods failed. Standard: $e, Isolate: $isolateError');
          throw Exception(
              'All decryption methods failed. Last error: $isolateError');
        }
      }

      // Parse the decrypted JSON with enhanced error handling
      debugPrint(
          '🔍 Attempting to parse decrypted JSON: ${decryptedJson.substring(0, math.min(100, decryptedJson.length))}...');

      Map<String, dynamic> contentMap;
      try {
        contentMap = jsonDecode(decryptedJson) as Map<String, dynamic>;
      } catch (jsonError) {
        debugPrint('❌ JSON parsing failed: $jsonError');
        debugPrint('🔍 Raw decrypted content: $decryptedJson');

        // If JSON parsing fails, treat the content as plain text
        contentMap = {
          'text': decryptedJson,
          'type': 'text',
          'formatted': false,
          'mentions': []
        };
      }

      // Extract components
      final text = contentMap['text'] as String? ?? '';

      MediaData? mediaData;
      if (contentMap['media'] != null) {
        mediaData = MediaData.fromJson(contentMap['media']);
      }

      LocationData? locationData;
      if (contentMap['location'] != null) {
        locationData = LocationData.fromJson(contentMap['location']);
      }

      CallData? callData;
      if (contentMap['call'] != null) {
        callData = CallData.fromJson(contentMap['call']);
      }

      decryptionStopwatch.stop();
      debugPrint(
          '✅ Message content decrypted successfully (${decryptionStopwatch.elapsedMilliseconds}ms)');

      return DecryptedMessageContent(
        text: text,
        mediaData: mediaData,
        locationData: locationData,
        callData: callData,
      );
    } catch (e) {
      decryptionStopwatch.stop();
      debugPrint(
          '❌ Error decrypting message content (${decryptionStopwatch.elapsedMilliseconds}ms): $e');

      // Return a fallback with error message for debugging
      return DecryptedMessageContent(
        text: '[Decryption Error: ${e.toString()}]',
        mediaData: null,
        locationData: null,
        callData: null,
      );
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
      debugPrint('❌ Error encrypting media data: $e');
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
      debugPrint('❌ Error decrypting media data: $e');
      return null;
    }
  }

  /// Encrypt a media file for upload
  Future<File?> encryptMediaFile(
    File mediaFile,
    String conversationId,
  ) async {
    try {
      debugPrint('🔐 Encrypting media file: ${mediaFile.path}');

      // Get conversation key
      final conversationKey = await _getConversationKey(conversationId);
      if (conversationKey == null) {
        debugPrint('❌ Failed to get conversation key for media encryption');
        return null;
      }

      // Read file data
      final mediaData = await mediaFile.readAsBytes();

      // Encrypt the data
      final encryptedData = await encryptMediaData(mediaData, conversationKey);
      if (encryptedData == null) {
        debugPrint('❌ Failed to encrypt media data');
        return null;
      }

      // Create encrypted file
      final tempDir = await getTemporaryDirectory();
      final encryptedFileName =
          '${_uuid.v4()}_encrypted${path.extension(mediaFile.path)}';
      final encryptedFile = File('${tempDir.path}/$encryptedFileName');
      await encryptedFile.writeAsBytes(encryptedData);

      debugPrint('✅ Media file encrypted successfully');
      return encryptedFile;
    } catch (e) {
      debugPrint('❌ Error encrypting media file: $e');
      return null;
    }
  }

  /// Decrypt a media file for display
  Future<File?> decryptMediaFile(
    File encryptedFile,
    String conversationId,
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

      // Get conversation key
      final conversationKey = await _getConversationKey(conversationId);
      if (conversationKey == null) {
        debugPrint('❌ Failed to get conversation key for media decryption');
        return null;
      }

      // Read encrypted data
      final encryptedData = await encryptedFile.readAsBytes();

      // Decrypt the data
      final decryptedData =
          await decryptMediaData(encryptedData, conversationKey);
      if (decryptedData == null) {
        debugPrint('❌ Failed to decrypt media data');
        return null;
      }

      // Create decrypted file
      final tempDir = await getTemporaryDirectory();
      final decryptedFileName =
          '${_uuid.v4()}_decrypted${path.extension(encryptedFile.path)}';
      final decryptedFile = File('${tempDir.path}/$decryptedFileName');
      await decryptedFile.writeAsBytes(decryptedData);

      debugPrint('✅ Media file decrypted successfully');
      return decryptedFile;
    } catch (e) {
      debugPrint('❌ Error decrypting media file: $e');
      return null;
    }
  }
}

/// Helper class for encrypted message content
class EncryptedMessageContent {
  final String content;
  final Map<String, dynamic> metadata;

  const EncryptedMessageContent({
    required this.content,
    required this.metadata,
  });
}

/// Helper class for decrypted message content
class DecryptedMessageContent {
  final String text;
  final MediaData? mediaData;
  final LocationData? locationData;
  final CallData? callData;

  const DecryptedMessageContent({
    required this.text,
    this.mediaData,
    this.locationData,
    this.callData,
  });
}
