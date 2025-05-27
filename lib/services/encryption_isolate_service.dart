import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';

/// Background isolate service for encryption operations to prevent UI blocking
class EncryptionIsolateService {
  static EncryptionIsolateService? _instance;
  static EncryptionIsolateService get instance =>
      _instance ??= EncryptionIsolateService._();

  EncryptionIsolateService._();

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  final Map<String, Completer<dynamic>> _pendingRequests = {};
  int _requestId = 0;

  /// Initialize the encryption isolate
  Future<void> initialize() async {
    if (_isolate != null) return;

    debugPrint('🔧 Initializing encryption isolate...');
    _receivePort = ReceivePort();

    _isolate = await Isolate.spawn(
      _encryptionIsolateEntryPoint,
      _receivePort!.sendPort,
    );

    // Listen for responses from isolate
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        debugPrint('✅ Encryption isolate initialized');
      } else if (message is Map<String, dynamic>) {
        final requestId = message['requestId'] as String;
        final completer = _pendingRequests.remove(requestId);

        if (completer != null) {
          if (message['error'] != null) {
            completer.completeError(Exception(message['error']));
          } else {
            completer.complete(message['result']);
          }
        }
      }
    });

    // Wait for isolate to be ready
    while (_sendPort == null) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Decrypt message in background isolate
  Future<String> decryptMessage({
    required String encryptedContent,
    required String conversationKey,
    required Map<String, dynamic> encryptionMetadata,
  }) async {
    await initialize();

    final requestId = 'decrypt_${_requestId++}';
    final completer = Completer<String>();
    _pendingRequests[requestId] = completer;

    _sendPort!.send({
      'type': 'decrypt',
      'requestId': requestId,
      'encryptedContent': encryptedContent,
      'conversationKey': conversationKey,
      'encryptionMetadata': encryptionMetadata,
    });

    return completer.future;
  }

  /// Encrypt message in background isolate
  Future<Map<String, dynamic>> encryptMessage({
    required String content,
    required String conversationKey,
  }) async {
    await initialize();

    final requestId = 'encrypt_${_requestId++}';
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestId] = completer;

    _sendPort!.send({
      'type': 'encrypt',
      'requestId': requestId,
      'content': content,
      'conversationKey': conversationKey,
    });

    return completer.future;
  }

  /// Dispose the isolate
  void dispose() {
    _isolate?.kill();
    _receivePort?.close();
    _isolate = null;
    _sendPort = null;
    _receivePort = null;
    _pendingRequests.clear();
    debugPrint('🔧 Encryption isolate disposed');
  }
}

/// Entry point for the encryption isolate
void _encryptionIsolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) async {
    if (message is Map<String, dynamic>) {
      try {
        final type = message['type'] as String;
        final requestId = message['requestId'] as String;

        dynamic result;

        if (type == 'decrypt') {
          result = await _performDecryption(
            message['encryptedContent'] as String,
            message['conversationKey'] as String,
            message['encryptionMetadata'] as Map<String, dynamic>,
          );
        } else if (type == 'encrypt') {
          result = await _performEncryption(
            message['content'] as String,
            message['conversationKey'] as String,
          );
        }

        mainSendPort.send({
          'requestId': requestId,
          'result': result,
        });
      } catch (e) {
        mainSendPort.send({
          'requestId': message['requestId'],
          'error': e.toString(),
        });
      }
    }
  });
}

/// Perform actual decryption in isolate - ENHANCED FOR COMPATIBILITY
Future<String> _performDecryption(
  String encryptedContent,
  String conversationKey,
  Map<String, dynamic> encryptionMetadata,
) async {
  final decryptionStopwatch = Stopwatch()..start();

  try {
    debugPrint('🔧 Starting isolate decryption');

    // ENHANCED COMPATIBILITY: Try multiple decryption formats
    try {
      // Method 1: Try to decode as combined format (new format)
      final decodedBytes = base64Decode(encryptedContent);
      final decodedJson = jsonDecode(utf8.decode(decodedBytes));

      // Extract metadata and ciphertext from the message content
      final metadata = decodedJson['metadata'] as Map<String, dynamic>;
      final ciphertext = decodedJson['ciphertext'] as String;

      // Extract encryption parameters from the embedded metadata
      final algorithm = metadata['algorithm'] as String?;
      final iv = metadata['iv'] as String?;
      final authTag = metadata['auth_tag'] as String?;
      final keyId = metadata['key_id'] as String?;

      if (algorithm != 'aes-256-gcm' ||
          iv == null ||
          authTag == null ||
          keyId == null) {
        throw Exception('Invalid embedded encryption metadata');
      }

      // Decode the encryption components
      final ivBytes = base64Decode(iv);
      final authTagBytes = base64Decode(authTag);
      final ciphertextBytes = base64Decode(ciphertext);
      final keyBytes = base64Decode(conversationKey);

      // Create AES-GCM cipher for decryption
      final aesGcm = AesGcm.with256bits();
      final secretKey = SecretKey(keyBytes);

      // Create SecretBox for decryption
      final secretBox = SecretBox(
        ciphertextBytes,
        nonce: ivBytes,
        mac: Mac(authTagBytes),
      );

      // Decrypt the data
      final decryptedBytes = await aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      // Decode the decrypted JSON content
      final decryptedJson = jsonDecode(utf8.decode(decryptedBytes));

      // Extract the actual message content
      if (decryptedJson is Map<String, dynamic>) {
        // Try 'text' field first (current format)
        if (decryptedJson.containsKey('text')) {
          return decryptedJson['text'] as String;
        }
        // Fall back to 'content' field (legacy format)
        else if (decryptedJson.containsKey('content')) {
          return decryptedJson['content'] as String;
        }
      }

      // If it's just a plain string, return it directly
      decryptionStopwatch.stop();
      debugPrint(
          '✅ Isolate decryption completed (${decryptionStopwatch.elapsedMilliseconds}ms)');
      return utf8.decode(decryptedBytes);
    } catch (e) {
      // Method 2: Try direct base64 decryption (for simple encrypted content)
      debugPrint('🔄 Combined format failed, trying direct decryption: $e');

      try {
        // Use AES-256-GCM for direct decryption
        final aesGcm = AesGcm.with256bits();
        final keyBytes = base64Decode(conversationKey);
        final secretKey = SecretKey(keyBytes);

        // Extract encryption parameters from metadata
        final iv = encryptionMetadata['iv'] as String?;
        final authTag = encryptionMetadata['auth_tag'] as String?;

        if (iv == null || authTag == null) {
          throw Exception('Missing IV or auth tag in metadata');
        }

        // Decode components
        final nonce = base64Decode(iv);
        final authTagBytes = base64Decode(authTag);
        final cipherTextBytes = base64Decode(encryptedContent);

        // Create SecretBox for decryption
        final secretBox = SecretBox(
          cipherTextBytes,
          nonce: nonce,
          mac: Mac(authTagBytes),
        );

        // Decrypt the data
        final decryptedBytes = await aesGcm.decrypt(
          secretBox,
          secretKey: secretKey,
        );

        decryptionStopwatch.stop();
        debugPrint(
            '✅ Direct isolate decryption completed (${decryptionStopwatch.elapsedMilliseconds}ms)');
        return utf8.decode(decryptedBytes);
      } catch (directError) {
        decryptionStopwatch.stop();
        debugPrint(
            '❌ All isolate decryption methods failed (${decryptionStopwatch.elapsedMilliseconds}ms)');
        throw Exception('Isolate decryption failed: $directError');
      }
    }
  } catch (e) {
    decryptionStopwatch.stop();
    throw Exception(
        'Decryption failed (${decryptionStopwatch.elapsedMilliseconds}ms): $e');
  }
}

/// Perform actual encryption in isolate - OPTIMIZED FOR PERFORMANCE
Future<Map<String, dynamic>> _performEncryption(
  String content,
  String conversationKey,
) async {
  final encryptionStopwatch = Stopwatch()..start();

  try {
    // PERFORMANCE OPTIMIZATION: Use proper AES-256-GCM encryption
    final aesGcm = AesGcm.with256bits();

    // Decode the conversation key
    final keyBytes = base64Decode(conversationKey);
    final secretKey = SecretKey(keyBytes);

    // Generate cryptographically secure random nonce (12 bytes for GCM)
    final nonce = List.generate(12, (i) => Random.secure().nextInt(256));

    // Convert content to bytes
    final contentBytes = utf8.encode(content);

    // Encrypt the data
    final secretBox = await aesGcm.encrypt(
      contentBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    encryptionStopwatch.stop();

    // Return encrypted data with metadata
    return {
      'encryptedContent': base64Encode(secretBox.cipherText),
      'metadata': {
        'algorithm': 'aes-256-gcm',
        'iv': base64Encode(nonce),
        'auth_tag': base64Encode(secretBox.mac.bytes),
        'version': 1,
      },
    };
  } catch (e) {
    encryptionStopwatch.stop();
    throw Exception(
        'Isolate encryption failed (${encryptionStopwatch.elapsedMilliseconds}ms): $e');
  }
}
