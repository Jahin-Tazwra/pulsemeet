import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/models/encryption_models.dart';

/// Signal Protocol-inspired encryption service for PulseMeet
class SignalProtocolService {
  static final SignalProtocolService _instance =
      SignalProtocolService._internal();
  factory SignalProtocolService() => _instance;
  SignalProtocolService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final SupabaseClient _supabase = Supabase.instance.client;
  final Random _random = Random.secure();

  // Key storage keys
  static const String _identityKeyPairKey = 'signal_identity_key_pair';
  static const String _registrationIdKey = 'signal_registration_id';
  static const String _preKeyIdKey = 'signal_prekey_id';

  // Session storage
  final Map<String, SessionState> _sessions = {};
  final Map<String, List<PreKeyBundle>> _preKeyBundles = {};

  bool _isInitialized = false;
  late IdentityKeyPair _identityKeyPair;
  late int _registrationId;
  int _nextPreKeyId = 1;

  /// Initialize the Signal Protocol service
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('🔐 Initializing Signal Protocol Service');

    try {
      // Load or generate identity key pair
      await _loadOrGenerateIdentityKeyPair();

      // Load or generate registration ID
      await _loadOrGenerateRegistrationId();

      // Load next pre-key ID
      await _loadNextPreKeyId();

      // Generate and upload pre-keys
      await _generateAndUploadPreKeys();

      _isInitialized = true;
      debugPrint('✅ Signal Protocol Service initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Signal Protocol Service: $e');
      rethrow;
    }
  }

  /// Load or generate identity key pair
  Future<void> _loadOrGenerateIdentityKeyPair() async {
    final storedKeyPair = await _secureStorage.read(key: _identityKeyPairKey);

    if (storedKeyPair != null) {
      final keyPairData = jsonDecode(storedKeyPair);
      _identityKeyPair = IdentityKeyPair.fromJson(keyPairData);
      debugPrint('🔑 Loaded existing identity key pair');
    } else {
      _identityKeyPair = _generateIdentityKeyPair();
      await _secureStorage.write(
        key: _identityKeyPairKey,
        value: jsonEncode(_identityKeyPair.toJson()),
      );
      debugPrint('🔑 Generated new identity key pair');
    }
  }

  /// Load or generate registration ID
  Future<void> _loadOrGenerateRegistrationId() async {
    final storedId = await _secureStorage.read(key: _registrationIdKey);

    if (storedId != null) {
      _registrationId = int.parse(storedId);
    } else {
      _registrationId = _generateRegistrationId();
      await _secureStorage.write(
        key: _registrationIdKey,
        value: _registrationId.toString(),
      );
    }
  }

  /// Load next pre-key ID
  Future<void> _loadNextPreKeyId() async {
    final storedId = await _secureStorage.read(key: _preKeyIdKey);

    if (storedId != null) {
      _nextPreKeyId = int.parse(storedId);
    }
  }

  /// Generate identity key pair
  IdentityKeyPair _generateIdentityKeyPair() {
    final keyGen = ECKeyGenerator();
    final secureRandom = FortunaRandom();

    // Seed the random number generator
    final seedSource = Random.secure();
    final seeds = <int>[];
    for (int i = 0; i < 32; i++) {
      seeds.add(seedSource.nextInt(256));
    }
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    final params = ECKeyGeneratorParameters(ECCurve_secp256r1());
    keyGen.init(ParametersWithRandom(params, secureRandom));

    final keyPair = keyGen.generateKeyPair();
    final privateKey = keyPair.privateKey as ECPrivateKey;
    final publicKey = keyPair.publicKey as ECPublicKey;

    return IdentityKeyPair(
      publicKey: IdentityKey(publicKey.Q!.getEncoded(false)),
      privateKey: _bigIntToBytes(privateKey.d!),
    );
  }

  /// Convert BigInt to bytes
  Uint8List _bigIntToBytes(BigInt bigInt) {
    final hex = bigInt.toRadixString(16);
    final paddedHex = hex.length % 2 == 0 ? hex : '0$hex';
    final bytes = <int>[];
    for (int i = 0; i < paddedHex.length; i += 2) {
      bytes.add(int.parse(paddedHex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// Generate registration ID
  int _generateRegistrationId() {
    return _random.nextInt(16384) + 1; // 1-16384 range
  }

  /// Generate and upload pre-keys
  Future<void> _generateAndUploadPreKeys() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Generate 100 one-time pre-keys
      final preKeys = <PreKey>[];
      for (int i = 0; i < 100; i++) {
        preKeys.add(_generatePreKey(_nextPreKeyId + i));
      }

      // Generate signed pre-key
      final signedPreKey = _generateSignedPreKey(_nextPreKeyId + 100);

      // Upload to Supabase
      await _uploadPreKeys(currentUserId, preKeys, signedPreKey);

      _nextPreKeyId += 101;
      await _secureStorage.write(
        key: _preKeyIdKey,
        value: _nextPreKeyId.toString(),
      );

      debugPrint('🔑 Generated and uploaded ${preKeys.length} pre-keys');
    } catch (e) {
      debugPrint('❌ Failed to generate and upload pre-keys: $e');
    }
  }

  /// Generate a pre-key
  PreKey _generatePreKey(int keyId) {
    final keyGen = ECKeyGenerator();
    final secureRandom = FortunaRandom();

    // Seed the random number generator
    final seedSource = Random.secure();
    final seeds = <int>[];
    for (int i = 0; i < 32; i++) {
      seeds.add(seedSource.nextInt(256));
    }
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    final params = ECKeyGeneratorParameters(ECCurve_secp256r1());
    keyGen.init(ParametersWithRandom(params, secureRandom));

    final keyPair = keyGen.generateKeyPair();
    final privateKey = keyPair.privateKey as ECPrivateKey;
    final publicKey = keyPair.publicKey as ECPublicKey;

    return PreKey(
      id: keyId,
      publicKey: publicKey.Q!.getEncoded(false),
      privateKey: _bigIntToBytes(privateKey.d!),
    );
  }

  /// Generate a signed pre-key
  SignedPreKey _generateSignedPreKey(int keyId) {
    final preKey = _generatePreKey(keyId);

    // Sign the public key with identity key
    final signature = _signData(preKey.publicKey, _identityKeyPair.privateKey);

    return SignedPreKey(
      id: keyId,
      publicKey: preKey.publicKey,
      privateKey: preKey.privateKey,
      signature: signature,
      timestamp: DateTime.now(),
    );
  }

  /// Sign data with private key
  Uint8List _signData(Uint8List data, Uint8List privateKey) {
    final signer = ECDSASigner(SHA256Digest());
    final privKey = ECPrivateKey(
      BigInt.parse(
          privateKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          radix: 16),
      ECCurve_secp256r1(),
    );

    signer.init(true, PrivateKeyParameter(privKey));
    final signature = signer.generateSignature(data) as ECSignature;

    // Encode signature as DER
    return _encodeDERSignature(signature);
  }

  /// Encode ECDSA signature as DER
  Uint8List _encodeDERSignature(ECSignature signature) {
    // Simple DER encoding for ECDSA signature
    final rBytes = _bigIntToBytes(signature.r);
    final sBytes = _bigIntToBytes(signature.s);

    final totalLength = 4 + rBytes.length + sBytes.length;
    final result = BytesBuilder();

    result.addByte(0x30); // SEQUENCE
    result.addByte(totalLength.toInt());
    result.addByte(0x02); // INTEGER
    result.addByte(rBytes.length);
    result.add(rBytes);
    result.addByte(0x02); // INTEGER
    result.addByte(sBytes.length);
    result.add(sBytes);

    return result.toBytes();
  }

  /// Upload pre-keys to Supabase
  Future<void> _uploadPreKeys(
    String userId,
    List<PreKey> preKeys,
    SignedPreKey signedPreKey,
  ) async {
    // Upload identity key and signed pre-key
    await _supabase.from('user_keys').upsert({
      'user_id': userId,
      'identity_key': base64Encode(_identityKeyPair.publicKey.publicKey),
      'registration_id': _registrationId,
      'signed_prekey_id': signedPreKey.id,
      'signed_prekey': base64Encode(signedPreKey.publicKey),
      'signed_prekey_signature': base64Encode(signedPreKey.signature),
      'signed_prekey_timestamp': signedPreKey.timestamp.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Upload one-time pre-keys
    final preKeyData = preKeys
        .map((preKey) => {
              'user_id': userId,
              'key_id': preKey.id,
              'public_key': base64Encode(preKey.publicKey),
              'created_at': DateTime.now().toIso8601String(),
            })
        .toList();

    if (preKeyData.isNotEmpty) {
      await _supabase.from('user_prekeys').insert(preKeyData);
    }
  }

  /// Encrypt a message for a conversation
  Future<EncryptedMessageData> encryptMessage(
    Message message,
    String conversationId,
  ) async {
    try {
      debugPrint(
          '🔐 Encrypting message ${message.id} for conversation $conversationId');

      // Get or create session for conversation
      final session = await _getOrCreateSession(conversationId);

      // Prepare message data
      final messageData = _prepareMessageData(message);
      final plaintext = utf8.encode(jsonEncode(messageData));

      // Encrypt with session
      final ciphertext = await _encryptWithSession(session, plaintext);

      // Create encryption metadata
      final metadata = EncryptionMetadata(
        algorithm: 'signal-protocol',
        version: 1,
        sessionId: session.sessionId,
        messageNumber: session.sendingChainKey.index,
        timestamp: DateTime.now(),
      );

      debugPrint('✅ Message encrypted successfully');

      return EncryptedMessageData(
        ciphertext: ciphertext,
        metadata: metadata,
      );
    } catch (e) {
      debugPrint('❌ Failed to encrypt message: $e');
      rethrow;
    }
  }

  /// Decrypt a message
  Future<Message> decryptMessage(Message encryptedMessage) async {
    try {
      debugPrint('🔓 Decrypting message ${encryptedMessage.id}');

      if (!encryptedMessage.isEncrypted ||
          encryptedMessage.encryptionMetadata == null) {
        return encryptedMessage; // Already decrypted or not encrypted
      }

      final metadata =
          EncryptionMetadata.fromJson(encryptedMessage.encryptionMetadata!);
      final session = _sessions[metadata.sessionId];

      if (session == null) {
        throw Exception('Session not found for message decryption');
      }

      // Decrypt ciphertext
      final ciphertext = base64Decode(encryptedMessage.content);
      final plaintext = await _decryptWithSession(session, ciphertext);

      // Parse decrypted data
      final messageData = jsonDecode(utf8.decode(plaintext));

      // Reconstruct message
      final decryptedMessage =
          _reconstructMessage(encryptedMessage, messageData);

      debugPrint('✅ Message decrypted successfully');

      return decryptedMessage;
    } catch (e) {
      debugPrint('❌ Failed to decrypt message: $e');
      return encryptedMessage.copyWith(
        content: '[Decryption failed]',
        isEncrypted: false,
      );
    }
  }

  /// Get or create session for conversation
  Future<SessionState> _getOrCreateSession(String conversationId) async {
    if (_sessions.containsKey(conversationId)) {
      return _sessions[conversationId]!;
    }

    // Create new session
    final session = await _createNewSession(conversationId);
    _sessions[conversationId] = session;

    return session;
  }

  /// Create new session for conversation
  Future<SessionState> _createNewSession(String conversationId) async {
    // For now, create a simple session
    // In a full Signal Protocol implementation, this would involve
    // key exchange with other participants

    final sessionId = _generateSessionId();
    final rootKey = _generateRandomBytes(32);
    final chainKey = ChainKey(key: _generateRandomBytes(32), index: 0);

    return SessionState(
      sessionId: sessionId,
      conversationId: conversationId,
      rootKey: rootKey,
      sendingChainKey: chainKey,
      receivingChainKey: chainKey,
      createdAt: DateTime.now(),
    );
  }

  /// Generate session ID
  String _generateSessionId() {
    final bytes = _generateRandomBytes(16);
    return base64Encode(bytes);
  }

  /// Generate random bytes
  Uint8List _generateRandomBytes(int length) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  /// Prepare message data for encryption
  Map<String, dynamic> _prepareMessageData(Message message) {
    return {
      'type': message.messageType.name,
      'content': message.content,
      'media_data': message.mediaData?.toJson(),
      'location_data': message.locationData?.toJson(),
      'call_data': message.callData?.toJson(),
      'mentions': message.mentions,
      'is_formatted': message.isFormatted,
      'reply_to_id': message.replyToId,
      'forward_from_id': message.forwardFromId,
    };
  }

  /// Encrypt with session
  Future<Uint8List> _encryptWithSession(
      SessionState session, Uint8List plaintext) async {
    // Simplified encryption using AES-GCM with session key
    final cipher = GCMBlockCipher(AESEngine());
    final key = session.sendingChainKey.key;
    final nonce = _generateRandomBytes(12);

    final params = AEADParameters(
      KeyParameter(key),
      128, // 128-bit authentication tag
      nonce,
      Uint8List(0), // No additional authenticated data
    );

    cipher.init(true, params);

    final ciphertext = cipher.process(plaintext);

    // Combine nonce and ciphertext
    final result = BytesBuilder();
    result.add(nonce);
    result.add(ciphertext);

    // Advance chain key
    session.sendingChainKey = _advanceChainKey(session.sendingChainKey);

    return result.toBytes();
  }

  /// Decrypt with session
  Future<Uint8List> _decryptWithSession(
      SessionState session, Uint8List ciphertext) async {
    // Extract nonce and ciphertext
    final nonce = ciphertext.sublist(0, 12);
    final actualCiphertext = ciphertext.sublist(12);

    final cipher = GCMBlockCipher(AESEngine());
    final key = session.receivingChainKey.key;

    final params = AEADParameters(
      KeyParameter(key),
      128, // 128-bit authentication tag
      nonce,
      Uint8List(0), // No additional authenticated data
    );

    cipher.init(false, params);

    final plaintext = cipher.process(actualCiphertext);

    // Advance chain key
    session.receivingChainKey = _advanceChainKey(session.receivingChainKey);

    return plaintext;
  }

  /// Advance chain key
  ChainKey _advanceChainKey(ChainKey chainKey) {
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(chainKey.key));

    final input = Uint8List.fromList([0x02]); // Chain key advancement constant
    final newKey = Uint8List(32);
    hmac.update(input, 0, input.length);
    hmac.doFinal(newKey, 0);

    return ChainKey(
      key: newKey,
      index: chainKey.index + 1,
    );
  }

  /// Reconstruct message from decrypted data
  Message _reconstructMessage(
      Message originalMessage, Map<String, dynamic> messageData) {
    return originalMessage.copyWith(
      content: messageData['content'] ?? '',
      mediaData: messageData['media_data'] != null
          ? MediaData.fromJson(messageData['media_data'])
          : null,
      locationData: messageData['location_data'] != null
          ? LocationData.fromJson(messageData['location_data'])
          : null,
      callData: messageData['call_data'] != null
          ? CallData.fromJson(messageData['call_data'])
          : null,
      mentions: List<String>.from(messageData['mentions'] ?? []),
      isFormatted: messageData['is_formatted'] ?? false,
      isEncrypted: false, // Mark as decrypted
    );
  }

  /// Get encryption status for conversation
  Future<ConversationEncryptionStatus> getEncryptionStatus(
      String conversationId) async {
    final session = _sessions[conversationId];

    if (session == null) {
      return ConversationEncryptionStatus(
        isEncrypted: false,
        encryptionLevel: EncryptionLevel.none,
        participantCount: 0,
        verifiedParticipants: 0,
      );
    }

    return ConversationEncryptionStatus(
      isEncrypted: true,
      encryptionLevel: EncryptionLevel.endToEnd,
      participantCount: 1, // TODO: Get actual participant count
      verifiedParticipants: 0, // TODO: Implement verification
      sessionId: session.sessionId,
      createdAt: session.createdAt,
    );
  }

  /// Dispose resources
  void dispose() {
    _sessions.clear();
    _preKeyBundles.clear();
    debugPrint('🧹 Signal Protocol Service disposed');
  }
}
