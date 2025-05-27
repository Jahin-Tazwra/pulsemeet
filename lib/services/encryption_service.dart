import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:pulsemeet/models/encryption_key.dart';

/// Core encryption service implementing Signal Protocol-like encryption
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  final _random = Random.secure();
  bool _isInitialized = false;

  // Cryptography algorithms
  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Initialize the encryption service
  Future<void> initialize() async {
    if (_isInitialized) return;

    _isInitialized = true;
    debugPrint('EncryptionService initialized');
  }

  /// Generate a new X25519 key pair for key exchange
  Future<EncryptionKeyPair> generateKeyPair({
    String? keyId,
    DateTime? expiresAt,
  }) async {
    await initialize();

    // Generate X25519 key pair
    final keyPair = await _x25519.newKeyPair();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKeyBytes = (await keyPair.extractPublicKey()).bytes;

    return EncryptionKeyPair(
      keyId: keyId ?? _generateKeyId(),
      publicKey: Uint8List.fromList(publicKeyBytes),
      privateKey: Uint8List.fromList(privateKeyBytes),
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      algorithm: 'x25519',
    );
  }

  /// Generate a shared secret using X25519 key exchange
  Future<Uint8List> generateSharedSecret(
    Uint8List privateKey,
    Uint8List publicKey,
  ) async {
    final privateKeyObj = SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    final publicKeyObj = SimplePublicKey(publicKey, type: KeyPairType.x25519);
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: privateKeyObj,
      remotePublicKey: publicKeyObj,
    );

    return Uint8List.fromList(await sharedSecret.extractBytes());
  }

  /// Derive a symmetric key from shared secret using HKDF
  Future<Uint8List> deriveSymmetricKey(
    Uint8List sharedSecret,
    String conversationId, {
    String salt = '',
    int keyLength = 32, // 256 bits for AES-256
  }) async {
    // Use HKDF (HMAC-based Key Derivation Function)
    final saltBytes = salt.isEmpty
        ? Uint8List(32) // Zero salt if not provided
        : Uint8List.fromList(utf8.encode(salt));

    final info =
        Uint8List.fromList(utf8.encode('PulseMeet-v1-$conversationId'));

    final derivedKey = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecret),
      nonce: saltBytes,
      info: info,
    );

    return Uint8List.fromList(await derivedKey.extractBytes());
  }

  /// Generate a random symmetric key for conversation
  Future<ConversationKey> generateConversationKey(
    String conversationId,
    ConversationType conversationType, {
    String? keyId,
    DateTime? expiresAt,
  }) async {
    await initialize();

    final symmetricKey = _generateRandomBytes(32); // 256-bit key

    return ConversationKey(
      keyId: keyId ?? _generateKeyId(),
      conversationId: conversationId,
      conversationType: conversationType,
      symmetricKey: symmetricKey,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
    );
  }

  /// Encrypt data using AES-256-GCM - OPTIMIZED FOR PERFORMANCE
  Future<EncryptedData> encryptData(
    Uint8List data,
    ConversationKey conversationKey, {
    Uint8List? additionalData,
  }) async {
    final encryptionStopwatch = Stopwatch()..start();

    await initialize();

    try {
      // PERFORMANCE OPTIMIZATION: Pre-generate nonce and key in parallel
      final nonce = _generateRandomBytes(12); // 96-bit nonce for GCM
      final secretKey = SecretKey(conversationKey.symmetricKey);

      // PERFORMANCE OPTIMIZATION: Use optimized encryption with minimal overhead
      final secretBox = await _aesGcm.encrypt(
        data,
        secretKey: secretKey,
        nonce: nonce,
        aad: additionalData ?? [],
      );

      final metadata = EncryptionMetadata(
        keyId: conversationKey.keyId,
        algorithm: 'aes-256-gcm',
        iv: nonce,
        authTag: base64Encode(secretBox.mac.bytes),
      );

      encryptionStopwatch.stop();
      debugPrint(
          '🔐 Core encryption completed (${encryptionStopwatch.elapsedMilliseconds}ms)');

      return EncryptedData(
        ciphertext: Uint8List.fromList(secretBox.cipherText),
        metadata: metadata,
      );
    } catch (e) {
      encryptionStopwatch.stop();
      debugPrint(
          '❌ Core encryption failed (${encryptionStopwatch.elapsedMilliseconds}ms): $e');
      rethrow;
    }
  }

  /// Decrypt data using AES-256-GCM
  Future<Uint8List> decryptData(
    EncryptedData encryptedData,
    ConversationKey conversationKey, {
    Uint8List? additionalData,
  }) async {
    await initialize();

    if (encryptedData.metadata.keyId != conversationKey.keyId) {
      throw Exception('Key ID mismatch');
    }

    // Create secret key
    final secretKey = SecretKey(conversationKey.symmetricKey);
    final authTag = base64Decode(encryptedData.metadata.authTag!);

    // Create SecretBox for decryption
    final secretBox = SecretBox(
      encryptedData.ciphertext,
      nonce: encryptedData.metadata.iv,
      mac: Mac(authTag),
    );

    // Decrypt the data
    try {
      final decryptedData = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
        aad: additionalData ?? [],
      );
      return Uint8List.fromList(decryptedData);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  /// Encrypt a text message
  Future<String> encryptMessage(
    String message,
    ConversationKey conversationKey,
  ) async {
    final messageBytes = Uint8List.fromList(utf8.encode(message));
    final encryptedData = await encryptData(messageBytes, conversationKey);

    // Combine metadata and ciphertext into a single string
    final combined = {
      'metadata': encryptedData.metadata.toJson(),
      'ciphertext': base64Encode(encryptedData.ciphertext),
    };

    return base64Encode(utf8.encode(jsonEncode(combined)));
  }

  /// Decrypt a text message
  Future<String> decryptMessage(
    String encryptedMessage,
    ConversationKey conversationKey,
  ) async {
    try {
      // Decode the combined data
      final combinedBytes = base64Decode(encryptedMessage);
      final combinedJson = jsonDecode(utf8.decode(combinedBytes));

      final metadata = EncryptionMetadata.fromJson(combinedJson['metadata']);
      final ciphertext = base64Decode(combinedJson['ciphertext']);

      final encryptedData = EncryptedData(
        ciphertext: ciphertext,
        metadata: metadata,
      );

      final decryptedBytes = await decryptData(encryptedData, conversationKey);
      return utf8.decode(decryptedBytes);
    } catch (e) {
      throw Exception('Message decryption failed: $e');
    }
  }

  /// Generate a random key ID
  String _generateKeyId() {
    final bytes = _generateRandomBytes(16);
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Generate cryptographically secure random bytes
  Uint8List _generateRandomBytes(int length) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  /// Securely clear sensitive data from memory
  void clearSensitiveData(Uint8List data) {
    for (int i = 0; i < data.length; i++) {
      data[i] = 0;
    }
  }
}

/// Represents encrypted data with metadata
class EncryptedData {
  final Uint8List ciphertext;
  final EncryptionMetadata metadata;

  EncryptedData({
    required this.ciphertext,
    required this.metadata,
  });
}
