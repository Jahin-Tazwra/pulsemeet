import 'dart:convert';
import 'dart:typed_data';

/// Identity key pair for Signal Protocol
class IdentityKeyPair {
  final IdentityKey publicKey;
  final Uint8List privateKey;

  const IdentityKeyPair({
    required this.publicKey,
    required this.privateKey,
  });

  factory IdentityKeyPair.fromJson(Map<String, dynamic> json) =>
      IdentityKeyPair(
        publicKey: IdentityKey.fromJson(json['publicKey']),
        privateKey: base64Decode(json['privateKey']),
      );

  Map<String, dynamic> toJson() => {
        'publicKey': publicKey.toJson(),
        'privateKey': base64Encode(privateKey),
      };
}

/// Identity key for Signal Protocol
class IdentityKey {
  final Uint8List publicKey;

  const IdentityKey(this.publicKey);

  factory IdentityKey.fromJson(Map<String, dynamic> json) =>
      IdentityKey(base64Decode(json['publicKey']));

  Map<String, dynamic> toJson() => {
        'publicKey': base64Encode(publicKey),
      };

  /// Get fingerprint for verification
  String getFingerprint() {
    // Generate a human-readable fingerprint
    final bytes = publicKey.take(20).toList();
    final groups = <String>[];

    for (int i = 0; i < bytes.length; i += 4) {
      final group = bytes
          .skip(i)
          .take(4)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join('');
      groups.add(group);
    }

    return groups.join(' ').toUpperCase();
  }
}

/// Pre-key for Signal Protocol
class PreKey {
  final int id;
  final Uint8List publicKey;
  final Uint8List privateKey;

  const PreKey({
    required this.id,
    required this.publicKey,
    required this.privateKey,
  });

  factory PreKey.fromJson(Map<String, dynamic> json) => PreKey(
        id: json['id'],
        publicKey: base64Decode(json['publicKey']),
        privateKey: base64Decode(json['privateKey']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'publicKey': base64Encode(publicKey),
        'privateKey': base64Encode(privateKey),
      };
}

/// Signed pre-key for Signal Protocol
class SignedPreKey {
  final int id;
  final Uint8List publicKey;
  final Uint8List privateKey;
  final Uint8List signature;
  final DateTime timestamp;

  const SignedPreKey({
    required this.id,
    required this.publicKey,
    required this.privateKey,
    required this.signature,
    required this.timestamp,
  });

  factory SignedPreKey.fromJson(Map<String, dynamic> json) => SignedPreKey(
        id: json['id'],
        publicKey: base64Decode(json['publicKey']),
        privateKey: base64Decode(json['privateKey']),
        signature: base64Decode(json['signature']),
        timestamp: DateTime.parse(json['timestamp']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'publicKey': base64Encode(publicKey),
        'privateKey': base64Encode(privateKey),
        'signature': base64Encode(signature),
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Pre-key bundle for key exchange
class PreKeyBundle {
  final String userId;
  final int registrationId;
  final IdentityKey identityKey;
  final SignedPreKey signedPreKey;
  final PreKey? oneTimePreKey;

  const PreKeyBundle({
    required this.userId,
    required this.registrationId,
    required this.identityKey,
    required this.signedPreKey,
    this.oneTimePreKey,
  });

  factory PreKeyBundle.fromJson(Map<String, dynamic> json) => PreKeyBundle(
        userId: json['userId'],
        registrationId: json['registrationId'],
        identityKey: IdentityKey.fromJson(json['identityKey']),
        signedPreKey: SignedPreKey.fromJson(json['signedPreKey']),
        oneTimePreKey: json['oneTimePreKey'] != null
            ? PreKey.fromJson(json['oneTimePreKey'])
            : null,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'registrationId': registrationId,
        'identityKey': identityKey.toJson(),
        'signedPreKey': signedPreKey.toJson(),
        'oneTimePreKey': oneTimePreKey?.toJson(),
      };
}

/// Session state for Signal Protocol
class SessionState {
  final String sessionId;
  final String conversationId;
  final Uint8List rootKey;
  ChainKey sendingChainKey;
  ChainKey receivingChainKey;
  final DateTime createdAt;
  DateTime? lastUsed;

  SessionState({
    required this.sessionId,
    required this.conversationId,
    required this.rootKey,
    required this.sendingChainKey,
    required this.receivingChainKey,
    required this.createdAt,
    this.lastUsed,
  });

  /// Update last used timestamp
  void updateLastUsed() {
    lastUsed = DateTime.now();
  }
}

/// Chain key for message encryption
class ChainKey {
  final Uint8List key;
  final int index;

  const ChainKey({
    required this.key,
    required this.index,
  });
}

/// Encrypted message data
class EncryptedMessageData {
  final Uint8List ciphertext;
  final EncryptionMetadata metadata;

  const EncryptedMessageData({
    required this.ciphertext,
    required this.metadata,
  });
}

/// Encryption metadata
class EncryptionMetadata {
  final String algorithm;
  final int version;
  final String sessionId;
  final int messageNumber;
  final DateTime timestamp;
  final Map<String, dynamic>? additionalData;

  const EncryptionMetadata({
    required this.algorithm,
    required this.version,
    required this.sessionId,
    required this.messageNumber,
    required this.timestamp,
    this.additionalData,
  });

  factory EncryptionMetadata.fromJson(Map<String, dynamic> json) =>
      EncryptionMetadata(
        algorithm: json['algorithm'],
        version: json['version'],
        sessionId: json['sessionId'],
        messageNumber: json['messageNumber'],
        timestamp: DateTime.parse(json['timestamp']),
        additionalData: json['additionalData'],
      );

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm,
        'version': version,
        'sessionId': sessionId,
        'messageNumber': messageNumber,
        'timestamp': timestamp.toIso8601String(),
        'additionalData': additionalData,
      };
}

/// Conversation encryption status
class ConversationEncryptionStatus {
  final bool isEncrypted;
  final EncryptionLevel encryptionLevel;
  final int participantCount;
  final int verifiedParticipants;
  final String? sessionId;
  final DateTime? createdAt;
  final List<SecurityEvent>? securityEvents;

  const ConversationEncryptionStatus({
    required this.isEncrypted,
    required this.encryptionLevel,
    required this.participantCount,
    required this.verifiedParticipants,
    this.sessionId,
    this.createdAt,
    this.securityEvents,
  });

  /// Get security score (0-100)
  int get securityScore {
    if (!isEncrypted) return 0;

    int score = 50; // Base score for encryption

    // Add points for encryption level
    switch (encryptionLevel) {
      case EncryptionLevel.endToEnd:
        score += 30;
        break;
      case EncryptionLevel.transport:
        score += 15;
        break;
      case EncryptionLevel.none:
        break;
    }

    // Add points for verified participants
    if (participantCount > 0) {
      final verificationRatio = verifiedParticipants / participantCount;
      score += (verificationRatio * 20).round();
    }

    return score.clamp(0, 100);
  }

  /// Get security level description
  String get securityDescription {
    final score = securityScore;

    if (score >= 90) return 'Excellent security';
    if (score >= 70) return 'Good security';
    if (score >= 50) return 'Basic security';
    if (score >= 30) return 'Limited security';
    return 'Poor security';
  }
}

/// Encryption levels
enum EncryptionLevel {
  none,
  transport,
  endToEnd,
}

/// Security event types
enum SecurityEventType {
  keyExchange,
  verification,
  keyRotation,
  securityWarning,
  encryptionFailure,
}

/// Security event
class SecurityEvent {
  final String id;
  final SecurityEventType type;
  final String description;
  final DateTime timestamp;
  final String? userId;
  final Map<String, dynamic>? metadata;

  const SecurityEvent({
    required this.id,
    required this.type,
    required this.description,
    required this.timestamp,
    this.userId,
    this.metadata,
  });
}

/// Disappearing message settings
class DisappearingMessageSettings {
  final bool enabled;
  final Duration duration;
  final DateTime? enabledAt;
  final String? enabledBy;

  const DisappearingMessageSettings({
    required this.enabled,
    required this.duration,
    this.enabledAt,
    this.enabledBy,
  });

  /// Get formatted duration string
  String get formattedDuration {
    if (duration.inDays > 0) {
      return '${duration.inDays} day${duration.inDays > 1 ? 's' : ''}';
    } else if (duration.inHours > 0) {
      return '${duration.inHours} hour${duration.inHours > 1 ? 's' : ''}';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes} minute${duration.inMinutes > 1 ? 's' : ''}';
    } else {
      return '${duration.inSeconds} second${duration.inSeconds > 1 ? 's' : ''}';
    }
  }
}

/// Key fingerprint for verification
class KeyFingerprint {
  final String userId;
  final String fingerprint;
  final DateTime generatedAt;
  final bool isVerified;
  final DateTime? verifiedAt;
  final String? verifiedBy;

  const KeyFingerprint({
    required this.userId,
    required this.fingerprint,
    required this.generatedAt,
    this.isVerified = false,
    this.verifiedAt,
    this.verifiedBy,
  });

  /// Get formatted fingerprint for display
  String get formattedFingerprint {
    // Split into groups of 4 characters
    final groups = <String>[];
    for (int i = 0; i < fingerprint.length; i += 4) {
      final end = (i + 4 < fingerprint.length) ? i + 4 : fingerprint.length;
      groups.add(fingerprint.substring(i, end));
    }
    return groups.join(' ');
  }
}
