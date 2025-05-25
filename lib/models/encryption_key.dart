import 'dart:convert';
import 'dart:typed_data';

/// Represents an encryption key pair for a user
class EncryptionKeyPair {
  final String keyId;
  final Uint8List publicKey;
  final Uint8List privateKey;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String algorithm; // 'x25519' or 'rsa2048'
  final bool isActive;

  EncryptionKeyPair({
    required this.keyId,
    required this.publicKey,
    required this.privateKey,
    required this.createdAt,
    this.expiresAt,
    this.algorithm = 'x25519',
    this.isActive = true,
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'key_id': keyId,
      'public_key': base64Encode(publicKey),
      'private_key': base64Encode(privateKey),
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'algorithm': algorithm,
      'is_active': isActive,
    };
  }

  /// Create from JSON
  factory EncryptionKeyPair.fromJson(Map<String, dynamic> json) {
    return EncryptionKeyPair(
      keyId: json['key_id'],
      publicKey: base64Decode(json['public_key']),
      privateKey: base64Decode(json['private_key']),
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: json['expires_at'] != null 
          ? DateTime.parse(json['expires_at']) 
          : null,
      algorithm: json['algorithm'] ?? 'x25519',
      isActive: json['is_active'] ?? true,
    );
  }

  /// Create a copy with updated fields
  EncryptionKeyPair copyWith({
    String? keyId,
    Uint8List? publicKey,
    Uint8List? privateKey,
    DateTime? createdAt,
    DateTime? expiresAt,
    String? algorithm,
    bool? isActive,
  }) {
    return EncryptionKeyPair(
      keyId: keyId ?? this.keyId,
      publicKey: publicKey ?? this.publicKey,
      privateKey: privateKey ?? this.privateKey,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      algorithm: algorithm ?? this.algorithm,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Represents a conversation encryption key
class ConversationKey {
  final String keyId;
  final String conversationId;
  final ConversationType conversationType;
  final Uint8List symmetricKey;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int version;
  final bool isActive;

  ConversationKey({
    required this.keyId,
    required this.conversationId,
    required this.conversationType,
    required this.symmetricKey,
    required this.createdAt,
    this.expiresAt,
    this.version = 1,
    this.isActive = true,
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'key_id': keyId,
      'conversation_id': conversationId,
      'conversation_type': conversationType.toString().split('.').last,
      'symmetric_key': base64Encode(symmetricKey),
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'version': version,
      'is_active': isActive,
    };
  }

  /// Create from JSON
  factory ConversationKey.fromJson(Map<String, dynamic> json) {
    return ConversationKey(
      keyId: json['key_id'],
      conversationId: json['conversation_id'],
      conversationType: ConversationType.values.firstWhere(
        (e) => e.toString().split('.').last == json['conversation_type'],
        orElse: () => ConversationType.direct,
      ),
      symmetricKey: base64Decode(json['symmetric_key']),
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: json['expires_at'] != null 
          ? DateTime.parse(json['expires_at']) 
          : null,
      version: json['version'] ?? 1,
      isActive: json['is_active'] ?? true,
    );
  }
}

/// Represents encrypted message metadata
class EncryptionMetadata {
  final String keyId;
  final String algorithm;
  final Uint8List iv; // Initialization Vector
  final String? authTag; // For authenticated encryption
  final int version;

  EncryptionMetadata({
    required this.keyId,
    required this.algorithm,
    required this.iv,
    this.authTag,
    this.version = 1,
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'key_id': keyId,
      'algorithm': algorithm,
      'iv': base64Encode(iv),
      'auth_tag': authTag,
      'version': version,
    };
  }

  /// Create from JSON
  factory EncryptionMetadata.fromJson(Map<String, dynamic> json) {
    return EncryptionMetadata(
      keyId: json['key_id'],
      algorithm: json['algorithm'],
      iv: base64Decode(json['iv']),
      authTag: json['auth_tag'],
      version: json['version'] ?? 1,
    );
  }
}

/// Conversation types for encryption
enum ConversationType {
  direct,
  pulse,
}

/// Encryption algorithms supported
enum EncryptionAlgorithm {
  aes256gcm,
  aes256cbc,
  chacha20poly1305,
}

/// Key exchange algorithms
enum KeyExchangeAlgorithm {
  x25519,
  rsa2048,
  curve25519,
}
