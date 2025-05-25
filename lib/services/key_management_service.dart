import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:pulsemeet/models/encryption_key.dart';
import 'package:pulsemeet/services/encryption_service.dart';

/// Manages encryption keys for users and conversations
class KeyManagementService {
  static final KeyManagementService _instance =
      KeyManagementService._internal();
  factory KeyManagementService() => _instance;
  KeyManagementService._internal();

  final _supabase = Supabase.instance.client;
  final _encryptionService = EncryptionService();
  final _uuid = const Uuid();

  // Secure storage for private keys
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // In-memory cache for conversation keys
  final Map<String, ConversationKey> _conversationKeyCache = {};

  // Current user's key pair
  EncryptionKeyPair? _currentUserKeyPair;
  String? _currentUserId;

  /// Initialize key management for current user
  Future<void> initialize() async {
    _currentUserId = _supabase.auth.currentUser?.id;
    if (_currentUserId == null) return;

    await _encryptionService.initialize();
    await _loadOrGenerateUserKeyPair();

    // Clear any cached pulse chat keys to force database lookup
    await _clearPulseChatKeysFromCache();

    debugPrint('KeyManagementService initialized for user: $_currentUserId');
  }

  /// Clear pulse chat keys from cache to force database lookup
  Future<void> _clearPulseChatKeysFromCache() async {
    debugPrint(
        '🔑 Cache clearing: Current cache keys: ${_conversationKeyCache.keys.toList()}');

    final keysToRemove = <String>[];
    for (final key in _conversationKeyCache.keys) {
      // Remove keys that look like pulse IDs (UUIDs) or don't start with 'dm_'
      if ((key.contains('-') && key.length == 36) || !key.startsWith('dm_')) {
        keysToRemove.add(key);
      }
    }

    debugPrint('🔑 Cache clearing: Keys to remove: $keysToRemove');

    for (final key in keysToRemove) {
      _conversationKeyCache.remove(key);
      debugPrint('🔑 Cleared cached pulse chat key: $key');
    }

    // Also clear pulse chat keys from secure storage
    await _clearPulseChatKeysFromSecureStorage();

    debugPrint(
        '🔑 Cache clearing: Remaining cache keys: ${_conversationKeyCache.keys.toList()}');
  }

  /// Clear pulse chat keys from secure storage
  Future<void> _clearPulseChatKeysFromSecureStorage() async {
    try {
      // Get all keys from secure storage
      final allKeys = await _secureStorage.readAll();

      final keysToDelete = <String>[];
      for (final key in allKeys.keys) {
        // Remove conversation keys that look like pulse IDs (UUIDs)
        if (key.startsWith('conversation_key_') &&
            !key.contains('dm_') &&
            key.contains('-')) {
          keysToDelete.add(key);
        }
      }

      debugPrint('🔑 Secure storage clearing: Keys to delete: $keysToDelete');

      for (final key in keysToDelete) {
        await _secureStorage.delete(key: key);
        debugPrint('🔑 Cleared pulse chat key from secure storage: $key');
      }
    } catch (e) {
      debugPrint('🔑 Error clearing pulse chat keys from secure storage: $e');
    }
  }

  /// Get current user's public key
  Uint8List? get currentUserPublicKey => _currentUserKeyPair?.publicKey;

  /// Get current user's key ID
  String? get currentUserKeyId => _currentUserKeyPair?.keyId;

  /// Get current user ID
  String? get currentUserId => _currentUserId;

  /// Check if the current user has a key pair
  bool get hasKeyPair => _currentUserKeyPair != null;

  /// Load or generate user's key pair
  Future<void> _loadOrGenerateUserKeyPair() async {
    if (_currentUserId == null) return;

    try {
      // Try to load existing key pair from secure storage
      final keyPairJson =
          await _secureStorage.read(key: 'user_keypair_$_currentUserId');

      if (keyPairJson != null) {
        _currentUserKeyPair =
            EncryptionKeyPair.fromJson(jsonDecode(keyPairJson));
        debugPrint('Loaded existing key pair for user');

        // Verify key pair is still valid
        if (_currentUserKeyPair!.expiresAt != null &&
            _currentUserKeyPair!.expiresAt!.isBefore(DateTime.now())) {
          debugPrint('Key pair expired, generating new one');
          await _generateAndStoreUserKeyPair();
        }
      } else {
        // Generate new key pair
        await _generateAndStoreUserKeyPair();
      }

      // Upload public key to server (non-blocking)
      _uploadPublicKey().catchError((e) {
        debugPrint('Non-critical error uploading public key: $e');
      });
    } catch (e) {
      debugPrint('Error loading key pair: $e');
      try {
        await _generateAndStoreUserKeyPair();
        // Try to upload the new key (non-blocking)
        _uploadPublicKey().catchError((e) {
          debugPrint('Non-critical error uploading new public key: $e');
        });
      } catch (e2) {
        debugPrint('Critical error generating key pair: $e2');
        // Continue without encryption if key generation fails
      }
    }
  }

  /// Generate and store new user key pair
  Future<void> _generateAndStoreUserKeyPair() async {
    if (_currentUserId == null) return;

    // Generate new key pair with 1 year expiration
    final expiresAt = DateTime.now().add(const Duration(days: 365));
    _currentUserKeyPair = await _encryptionService.generateKeyPair(
      expiresAt: expiresAt,
    );

    // Store securely
    await _secureStorage.write(
      key: 'user_keypair_$_currentUserId',
      value: jsonEncode(_currentUserKeyPair!.toJson()),
    );

    debugPrint('Generated and stored new key pair');
  }

  /// Upload public key to server
  Future<void> _uploadPublicKey() async {
    if (_currentUserKeyPair == null || _currentUserId == null) return;

    try {
      // First, check if this key already exists
      final existingKey = await _supabase
          .from('user_public_keys')
          .select('id')
          .eq('user_id', _currentUserId)
          .eq('key_id', _currentUserKeyPair!.keyId)
          .maybeSingle();

      if (existingKey != null) {
        debugPrint('Public key already exists, skipping upload');
        return;
      }

      // Deactivate old keys first
      await _supabase
          .from('user_public_keys')
          .update({'is_active': false})
          .eq('user_id', _currentUserId)
          .eq('is_active', true);

      // Insert new key
      await _supabase.from('user_public_keys').insert({
        'user_id': _currentUserId,
        'key_id': _currentUserKeyPair!.keyId,
        'public_key': base64Encode(_currentUserKeyPair!.publicKey),
        'algorithm': _currentUserKeyPair!.algorithm,
        'created_at': _currentUserKeyPair!.createdAt.toIso8601String(),
        'expires_at': _currentUserKeyPair!.expiresAt?.toIso8601String(),
        'is_active': _currentUserKeyPair!.isActive,
      });

      debugPrint('Uploaded public key to server');
    } catch (e) {
      debugPrint('Error uploading public key: $e');
      // Don't rethrow - this is not critical for app functionality
    }
  }

  /// Get public key for another user
  Future<Uint8List?> getUserPublicKey(String userId) async {
    try {
      final response = await _supabase
          .from('user_public_keys')
          .select('public_key')
          .eq('user_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        return base64Decode(response['public_key']);
      }
    } catch (e) {
      debugPrint('Error fetching user public key: $e');
    }
    return null;
  }

  /// Create or get conversation key for direct message
  Future<ConversationKey?> getOrCreateDirectMessageKey(String otherUserId,
      {String? actualConversationId}) async {
    // Use actual conversation ID if provided, otherwise generate one
    final conversationId =
        actualConversationId ?? _getDirectMessageConversationId(otherUserId);

    debugPrint('🔑 Getting DM key for conversation: $conversationId');
    debugPrint('🔑 Other user: $otherUserId');
    debugPrint('🔑 Actual conversation ID provided: $actualConversationId');

    // For direct messages with actual conversation ID, check shared key storage first
    if (actualConversationId != null) {
      debugPrint('🔑 Checking shared DM key storage for: $conversationId');
      final sharedKey = await _getSharedDirectMessageKey(conversationId);
      if (sharedKey != null) {
        debugPrint('🔑 ✅ Retrieved shared DM key: ${sharedKey.keyId}');
        _conversationKeyCache[conversationId] = sharedKey;
        await _storeConversationKey(sharedKey);
        return sharedKey;
      }
    }

    // Check cache
    if (_conversationKeyCache.containsKey(conversationId)) {
      debugPrint('🔑 Found cached key for conversation: $conversationId');
      return _conversationKeyCache[conversationId];
    }

    // Try to load from secure storage
    final storedKey = await _loadConversationKey(conversationId);
    if (storedKey != null) {
      debugPrint('🔑 Loaded stored key for conversation: $conversationId');
      _conversationKeyCache[conversationId] = storedKey;
      return storedKey;
    }

    // Create new conversation key
    debugPrint(
        '🔑 Creating new shared DM key for conversation: $conversationId');
    return await _createSharedDirectMessageKey(conversationId, otherUserId);
  }

  /// Get shared direct message key from database
  Future<ConversationKey?> _getSharedDirectMessageKey(
      String conversationId) async {
    try {
      debugPrint(
          '🔑 Querying database for shared DM key: conversation_id=$conversationId');

      final response = await _supabase
          .from('direct_message_keys')
          .select(
              'key_id, symmetric_key, created_at, expires_at, version, is_active')
          .eq('conversation_id', conversationId)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      debugPrint('🔑 Database response: $response');

      if (response != null) {
        final conversationKey = ConversationKey(
          keyId: response['key_id'],
          conversationId: conversationId,
          conversationType: ConversationType.direct,
          symmetricKey: base64Decode(response['symmetric_key']),
          createdAt: DateTime.parse(response['created_at']),
          expiresAt: response['expires_at'] != null
              ? DateTime.parse(response['expires_at'])
              : null,
          version: response['version'] ?? 1,
          isActive: response['is_active'] ?? true,
        );

        debugPrint(
            '🔑 ✅ Successfully retrieved shared DM key with keyId: ${conversationKey.keyId}');
        return conversationKey;
      } else {
        debugPrint(
            '🔑 ❌ No shared DM key found in database for conversation: $conversationId');
      }
    } catch (e) {
      debugPrint('🔑 ❌ Error fetching shared DM key: $e');
    }
    return null;
  }

  /// Create new shared direct message key and store in database
  Future<ConversationKey?> _createSharedDirectMessageKey(
      String conversationId, String otherUserId) async {
    if (_currentUserId == null || _currentUserKeyPair == null) {
      debugPrint(
          '🔑 ❌ Cannot create shared DM key: no current user or key pair');
      return null;
    }

    try {
      debugPrint(
          '🔑 Generating new shared DM key for conversation: $conversationId');

      // Get other user's public key
      final otherUserPublicKey = await getUserPublicKey(otherUserId);
      if (otherUserPublicKey == null) {
        throw Exception('Cannot find public key for user: $otherUserId');
      }

      // Generate shared secret using X25519
      final sharedSecret = await _encryptionService.generateSharedSecret(
        _currentUserKeyPair!.privateKey,
        otherUserPublicKey,
      );

      // Derive symmetric key using the conversation ID
      final symmetricKey = await _encryptionService.deriveSymmetricKey(
        sharedSecret,
        conversationId,
      );

      // Generate conversation key
      final conversationKey = ConversationKey(
        keyId: _uuid.v4(),
        conversationId: conversationId,
        conversationType: ConversationType.direct,
        symmetricKey: symmetricKey,
        createdAt: DateTime.now(),
      );

      debugPrint('🔑 Generated DM key with ID: ${conversationKey.keyId}');
      debugPrint('🔑 Attempting to store in database...');

      // Store in database for other user to access
      final response = await _supabase.from('direct_message_keys').upsert({
        'conversation_id': conversationId,
        'key_id': conversationKey.keyId,
        'symmetric_key': base64Encode(conversationKey.symmetricKey),
        'created_by': _currentUserId,
        'created_at': conversationKey.createdAt.toIso8601String(),
        'expires_at': conversationKey.expiresAt?.toIso8601String(),
        'version': conversationKey.version,
        'is_active': true,
      });

      // Store locally
      await _storeConversationKey(conversationKey);
      _conversationKeyCache[conversationId] = conversationKey;

      // Clear sensitive data
      _encryptionService.clearSensitiveData(sharedSecret);
      _encryptionService.clearSensitiveData(symmetricKey);

      debugPrint(
          '🔑 ✅ Successfully stored shared DM key in database for: $conversationId');
      debugPrint('🔑 Database response: $response');
      return conversationKey;
    } catch (e) {
      debugPrint('🔑 ❌ Error creating shared DM key: $e');
      debugPrint('🔑 ❌ Error type: ${e.runtimeType}');
      if (e is PostgrestException) {
        debugPrint(
            '🔑 ❌ PostgrestException details: ${e.message}, code: ${e.code}');
      }
      return null;
    }
  }

  /// Create or get conversation key for pulse chat
  Future<ConversationKey?> getOrCreatePulseChatKey(String pulseId) async {
    debugPrint('🔑 getOrCreatePulseChatKey called for pulse: $pulseId');
    debugPrint('🔑 Current user: $_currentUserId');

    // For pulse chats, ALWAYS check database first for shared keys
    debugPrint(
        '🔑 Attempting to retrieve shared key from database for pulse: $pulseId');
    final sharedKey = await _getSharedPulseChatKey(pulseId);
    if (sharedKey != null) {
      debugPrint(
          '🔑 Retrieved shared pulse chat key for: $pulseId with keyId: ${sharedKey.keyId}');
      _conversationKeyCache[pulseId] = sharedKey;
      await _storeConversationKey(sharedKey);
      return sharedKey;
    }

    // Check cache for existing shared key (but only if database check failed)
    if (_conversationKeyCache.containsKey(pulseId)) {
      final cachedKey = _conversationKeyCache[pulseId];
      debugPrint(
          '🔑 Found cached key for pulse $pulseId with keyId: ${cachedKey?.keyId}');
      debugPrint(
          '🔑 ⚠️ Using cached key but it was not in database - this may cause issues');
      return cachedKey;
    }

    // Create new shared conversation key for the pulse
    debugPrint(
        '🔑 No existing shared key found, creating new one for pulse: $pulseId');
    final conversationKey = await _createSharedPulseChatKey(pulseId);
    if (conversationKey != null) {
      await _storeConversationKey(conversationKey);
      _conversationKeyCache[pulseId] = conversationKey;
      debugPrint(
          '🔑 Created new shared pulse chat key for: $pulseId with keyId: ${conversationKey.keyId}');
    } else {
      debugPrint('🔑 ❌ Failed to create shared pulse chat key for: $pulseId');
    }

    return conversationKey;
  }

  /// Store conversation key securely
  Future<void> _storeConversationKey(ConversationKey key) async {
    await _secureStorage.write(
      key: 'conversation_key_${key.conversationId}',
      value: jsonEncode(key.toJson()),
    );
  }

  /// Load conversation key from secure storage
  Future<ConversationKey?> _loadConversationKey(String conversationId) async {
    try {
      final keyJson =
          await _secureStorage.read(key: 'conversation_key_$conversationId');
      if (keyJson != null) {
        return ConversationKey.fromJson(jsonDecode(keyJson));
      }
    } catch (e) {
      debugPrint('Error loading conversation key: $e');
    }
    return null;
  }

  /// Get shared pulse chat key from database
  Future<ConversationKey?> _getSharedPulseChatKey(String pulseId) async {
    try {
      debugPrint(
          '🔑 Querying database for shared key: pulse_id=$pulseId, user=$_currentUserId');

      final response = await _supabase
          .from('pulse_chat_keys')
          .select('*')
          .eq('pulse_id', pulseId)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      debugPrint('🔑 Database response: $response');

      if (response != null) {
        final conversationKey = ConversationKey(
          keyId: response['key_id'],
          conversationId: pulseId,
          conversationType: ConversationType.pulse,
          symmetricKey: base64Decode(response['symmetric_key']),
          createdAt: DateTime.parse(response['created_at']),
          expiresAt: response['expires_at'] != null
              ? DateTime.parse(response['expires_at'])
              : null,
          version: response['version'] ?? 1,
          isActive: response['is_active'] ?? true,
        );

        debugPrint(
            '🔑 ✅ Successfully created ConversationKey from database with keyId: ${conversationKey.keyId}');
        return conversationKey;
      } else {
        debugPrint('🔑 ❌ No shared key found in database for pulse: $pulseId');
      }
    } catch (e) {
      debugPrint('🔑 ❌ Error fetching shared pulse chat key: $e');
    }
    return null;
  }

  /// Create new shared pulse chat key and store in database
  Future<ConversationKey?> _createSharedPulseChatKey(String pulseId) async {
    if (_currentUserId == null) {
      debugPrint('🔑 ❌ Cannot create shared key: no current user');
      return null;
    }

    try {
      debugPrint('🔑 Generating new conversation key for pulse: $pulseId');

      // Generate new conversation key
      final conversationKey = await _encryptionService.generateConversationKey(
        pulseId,
        ConversationType.pulse,
      );

      debugPrint('🔑 Generated key with ID: ${conversationKey.keyId}');
      debugPrint('🔑 Attempting to store in database...');

      // Store in database for other users to access
      final response = await _supabase.from('pulse_chat_keys').upsert({
        'pulse_id': pulseId,
        'key_id': conversationKey.keyId,
        'symmetric_key': base64Encode(conversationKey.symmetricKey),
        'created_by': _currentUserId,
        'created_at': conversationKey.createdAt.toIso8601String(),
        'expires_at': conversationKey.expiresAt?.toIso8601String(),
        'version': conversationKey.version,
        'is_active': true,
      });

      debugPrint(
          '🔑 ✅ Successfully stored shared pulse chat key in database for: $pulseId');
      debugPrint('🔑 Database response: $response');
      return conversationKey;
    } catch (e) {
      debugPrint('🔑 ❌ Error creating shared pulse chat key: $e');
      debugPrint('🔑 ❌ Error type: ${e.runtimeType}');
      if (e is PostgrestException) {
        debugPrint(
            '🔑 ❌ PostgrestException details: ${e.message}, code: ${e.code}');
      }
      return null;
    }
  }

  /// Clear cached key for a pulse (for debugging)
  void clearPulseChatKeyCache(String pulseId) {
    _conversationKeyCache.remove(pulseId);
    debugPrint('🔑 Cleared cached key for pulse: $pulseId');
  }

  /// Generate conversation ID for direct messages
  String _getDirectMessageConversationId(String otherUserId) {
    final userIds = [_currentUserId!, otherUserId]..sort();
    return 'dm_${userIds[0]}_${userIds[1]}';
  }

  /// Rotate user key pair
  Future<void> rotateUserKeyPair() async {
    await _generateAndStoreUserKeyPair();
    await _uploadPublicKey();
    debugPrint('User key pair rotated');
  }

  /// Clear all cached keys
  void clearCache() {
    _conversationKeyCache.clear();
    debugPrint('Key cache cleared');
  }

  /// Delete conversation key
  Future<void> deleteConversationKey(String conversationId) async {
    await _secureStorage.delete(key: 'conversation_key_$conversationId');
    _conversationKeyCache.remove(conversationId);
    debugPrint('Deleted conversation key: $conversationId');
  }

  /// Verify key fingerprint for security verification
  String getKeyFingerprint(Uint8List publicKey) {
    final digest = sha256.convert(publicKey);
    return digest.toString().substring(0, 16).toUpperCase();
  }

  /// Clean up resources
  void dispose() {
    _conversationKeyCache.clear();
    _currentUserKeyPair = null;
    _currentUserId = null;
  }
}
