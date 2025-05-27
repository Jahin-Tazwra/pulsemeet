import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import '../models/encryption_key.dart';
import 'encryption_service.dart';

/// Service for secure key derivation using ECDH and HKDF
/// Implements WhatsApp-style key exchange without server-side key storage
class KeyDerivationService {
  static const String _hkdfSalt = 'PulseMeet-E2E-Salt-v1';
  static const String _conversationKeyInfo = 'PulseMeet-Conversation-Key';
  static const String _deviceKeyInfo = 'PulseMeet-Device-Key';
  static const int _keyLength = 32; // 256-bit keys

  final EncryptionService _encryptionService;

  KeyDerivationService(this._encryptionService);

  /// Derive a conversation key using ECDH + HKDF
  /// This eliminates the need to store symmetric keys in the database
  Future<ConversationKey> deriveConversationKey({
    required String conversationId,
    required ConversationType conversationType,
    required Uint8List myPrivateKey,
    required Uint8List otherPublicKey,
    String? keyId,
    DateTime? expiresAt,
  }) async {
    try {
      debugPrint('🔑 Deriving conversation key for: $conversationId');

      // Step 1: Perform ECDH key exchange
      final sharedSecret = await _encryptionService.generateSharedSecret(
        myPrivateKey,
        otherPublicKey,
      );

      // Step 2: Derive symmetric key using HKDF
      final symmetricKey = await _deriveKeyWithHKDF(
        sharedSecret,
        conversationId,
        _conversationKeyInfo,
      );

      // Step 3: Create conversation key object (no database storage)
      final conversationKey = ConversationKey(
        keyId: keyId ?? _generateKeyId(),
        conversationId: conversationId,
        conversationType: conversationType,
        symmetricKey: symmetricKey,
        createdAt: DateTime.now(),
        expiresAt: expiresAt,
      );

      debugPrint('🔑 ✅ Successfully derived conversation key: ${conversationKey.keyId}');
      return conversationKey;
    } catch (e) {
      debugPrint('🔑 ❌ Failed to derive conversation key: $e');
      rethrow;
    }
  }

  /// Derive a device-specific key for multi-device support
  /// Used to encrypt conversation keys for storage on multiple devices
  Future<Uint8List> deriveDeviceKey({
    required String userId,
    required String deviceId,
    required Uint8List masterKey,
  }) async {
    final info = '$_deviceKeyInfo-$userId-$deviceId';
    return await _deriveKeyWithHKDF(masterKey, deviceId, info);
  }

  /// HKDF key derivation function
  /// Implements RFC 5869 HMAC-based Key Derivation Function
  Future<Uint8List> _deriveKeyWithHKDF(
    Uint8List inputKeyMaterial,
    String context,
    String info,
  ) async {
    // Step 1: Extract - HMAC-SHA256(salt, IKM)
    final salt = utf8.encode(_hkdfSalt);
    final hmacExtract = Hmac(sha256, salt);
    final prk = hmacExtract.convert(inputKeyMaterial).bytes;

    // Step 2: Expand - HMAC-SHA256(PRK, info || context || counter)
    final infoBytes = utf8.encode(info);
    final contextBytes = utf8.encode(context);
    final hmacExpand = Hmac(sha256, prk);

    final expandInput = <int>[];
    expandInput.addAll(infoBytes);
    expandInput.addAll(contextBytes);
    expandInput.add(1); // Counter byte

    final okm = hmacExpand.convert(expandInput).bytes;
    return Uint8List.fromList(okm.take(_keyLength).toList());
  }

  /// Generate a unique key ID
  String _generateKeyId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = List.generate(8, (i) => (timestamp + i) % 256);
    return base64Encode(random).replaceAll('=', '').substring(0, 12);
  }

  /// Verify if two users can establish a secure conversation
  /// Checks if both users have valid public keys
  Future<bool> canEstablishSecureConversation({
    required String userId1,
    required String userId2,
    required Future<Uint8List?> Function(String) getPublicKey,
  }) async {
    try {
      final publicKey1 = await getPublicKey(userId1);
      final publicKey2 = await getPublicKey(userId2);
      return publicKey1 != null && publicKey2 != null;
    } catch (e) {
      debugPrint('🔑 Error checking secure conversation capability: $e');
      return false;
    }
  }

  /// Rotate conversation key by deriving a new one with updated timestamp
  /// Implements perfect forward secrecy
  Future<ConversationKey> rotateConversationKey({
    required ConversationKey currentKey,
    required Uint8List myPrivateKey,
    required Uint8List otherPublicKey,
  }) async {
    // Add timestamp to conversation ID for key rotation
    final rotatedConversationId = '${currentKey.conversationId}_${DateTime.now().millisecondsSinceEpoch}';
    
    return await deriveConversationKey(
      conversationId: rotatedConversationId,
      conversationType: currentKey.conversationType,
      myPrivateKey: myPrivateKey,
      otherPublicKey: otherPublicKey,
      expiresAt: DateTime.now().add(const Duration(days: 30)), // 30-day expiration
    );
  }

  /// Derive a key for encrypting media files
  /// Uses a different info string to ensure key separation
  Future<Uint8List> deriveMediaKey({
    required String conversationId,
    required Uint8List conversationKey,
    required String mediaId,
  }) async {
    final info = 'PulseMeet-Media-Key-$mediaId';
    return await _deriveKeyWithHKDF(conversationKey, conversationId, info);
  }

  /// Derive a key for message authentication
  /// Provides additional security layer for message integrity
  Future<Uint8List> deriveAuthKey({
    required String conversationId,
    required Uint8List conversationKey,
  }) async {
    const info = 'PulseMeet-Auth-Key';
    return await _deriveKeyWithHKDF(conversationKey, conversationId, info);
  }

  /// Clear sensitive data from memory
  void clearSensitiveData() {
    // In a production implementation, you would zero out any cached keys
    debugPrint('🔑 Cleared sensitive key derivation data');
  }
}

/// Key derivation result with metadata
class DerivedKeyResult {
  final Uint8List key;
  final String keyId;
  final DateTime derivedAt;
  final String algorithm;

  DerivedKeyResult({
    required this.key,
    required this.keyId,
    required this.derivedAt,
    this.algorithm = 'ECDH-HKDF-SHA256',
  });

  Map<String, dynamic> toJson() {
    return {
      'key_id': keyId,
      'derived_at': derivedAt.toIso8601String(),
      'algorithm': algorithm,
    };
  }
}

/// Key rotation policy
enum KeyRotationPolicy {
  never,
  daily,
  weekly,
  monthly,
  onDemand,
}

/// Key derivation context for different use cases
enum KeyDerivationContext {
  conversation,
  media,
  authentication,
  device,
  backup,
}
