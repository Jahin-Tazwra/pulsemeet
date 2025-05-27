import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemeet/services/key_derivation_service.dart';
import 'package:pulsemeet/services/encryption_service.dart';
import 'package:pulsemeet/models/encryption_key.dart';
import 'dart:typed_data';

void main() {
  group('Secure Key Exchange Tests', () {
    late EncryptionService encryptionService;
    late KeyDerivationService keyDerivationService;

    setUp(() async {
      encryptionService = EncryptionService();
      await encryptionService.initialize();
      keyDerivationService = KeyDerivationService(encryptionService);
    });

    test('ECDH key derivation produces identical keys for both parties', () async {
      // Simulate two users: Alice and Bob
      final aliceKeyPair = await encryptionService.generateKeyPair();
      final bobKeyPair = await encryptionService.generateKeyPair();
      
      const conversationId = 'dm_alice_bob';

      // Alice derives conversation key
      final aliceConversationKey = await keyDerivationService.deriveConversationKey(
        conversationId: conversationId,
        conversationType: ConversationType.direct,
        myPrivateKey: aliceKeyPair.privateKey,
        otherPublicKey: bobKeyPair.publicKey,
      );

      // Bob derives the same conversation key
      final bobConversationKey = await keyDerivationService.deriveConversationKey(
        conversationId: conversationId,
        conversationType: ConversationType.direct,
        myPrivateKey: bobKeyPair.privateKey,
        otherPublicKey: aliceKeyPair.publicKey,
      );

      // Both should derive identical symmetric keys
      expect(aliceConversationKey.symmetricKey, equals(bobConversationKey.symmetricKey));
      expect(aliceConversationKey.conversationId, equals(bobConversationKey.conversationId));
    });

    test('Different conversation IDs produce different keys', () async {
      final aliceKeyPair = await encryptionService.generateKeyPair();
      final bobKeyPair = await encryptionService.generateKeyPair();

      // Derive keys for two different conversations
      final conversation1Key = await keyDerivationService.deriveConversationKey(
        conversationId: 'dm_alice_bob_1',
        conversationType: ConversationType.direct,
        myPrivateKey: aliceKeyPair.privateKey,
        otherPublicKey: bobKeyPair.publicKey,
      );

      final conversation2Key = await keyDerivationService.deriveConversationKey(
        conversationId: 'dm_alice_bob_2',
        conversationType: ConversationType.direct,
        myPrivateKey: aliceKeyPair.privateKey,
        otherPublicKey: bobKeyPair.publicKey,
      );

      // Keys should be different for different conversations
      expect(conversation1Key.symmetricKey, isNot(equals(conversation2Key.symmetricKey)));
    });

    test('Key rotation produces new keys while maintaining derivability', () async {
      final aliceKeyPair = await encryptionService.generateKeyPair();
      final bobKeyPair = await encryptionService.generateKeyPair();

      // Original conversation key
      final originalKey = await keyDerivationService.deriveConversationKey(
        conversationId: 'dm_alice_bob',
        conversationType: ConversationType.direct,
        myPrivateKey: aliceKeyPair.privateKey,
        otherPublicKey: bobKeyPair.publicKey,
      );

      // Rotate the key
      final rotatedKey = await keyDerivationService.rotateConversationKey(
        currentKey: originalKey,
        myPrivateKey: aliceKeyPair.privateKey,
        otherPublicKey: bobKeyPair.publicKey,
      );

      // Rotated key should be different
      expect(rotatedKey.symmetricKey, isNot(equals(originalKey.symmetricKey)));
      expect(rotatedKey.conversationId, isNot(equals(originalKey.conversationId)));
      
      // But Bob should be able to derive the same rotated key
      final bobRotatedKey = await keyDerivationService.deriveConversationKey(
        conversationId: rotatedKey.conversationId,
        conversationType: ConversationType.direct,
        myPrivateKey: bobKeyPair.privateKey,
        otherPublicKey: aliceKeyPair.publicKey,
      );

      expect(rotatedKey.symmetricKey, equals(bobRotatedKey.symmetricKey));
    });

    test('Media key derivation produces consistent results', () async {
      final conversationKey = Uint8List.fromList(List.generate(32, (i) => i));
      const conversationId = 'test_conversation';
      const mediaId = 'media_123';

      // Derive media key multiple times
      final mediaKey1 = await keyDerivationService.deriveMediaKey(
        conversationId: conversationId,
        conversationKey: conversationKey,
        mediaId: mediaId,
      );

      final mediaKey2 = await keyDerivationService.deriveMediaKey(
        conversationId: conversationId,
        conversationKey: conversationKey,
        mediaId: mediaId,
      );

      // Should produce identical results
      expect(mediaKey1, equals(mediaKey2));
      
      // Should be different from conversation key
      expect(mediaKey1, isNot(equals(conversationKey)));
    });

    test('Authentication key derivation works correctly', () async {
      final conversationKey = Uint8List.fromList(List.generate(32, (i) => i));
      const conversationId = 'test_conversation';

      final authKey = await keyDerivationService.deriveAuthKey(
        conversationId: conversationId,
        conversationKey: conversationKey,
      );

      // Auth key should be different from conversation key
      expect(authKey, isNot(equals(conversationKey)));
      expect(authKey.length, equals(32)); // 256-bit key
    });

    test('End-to-end encryption and decryption with derived keys', () async {
      // Setup two users
      final aliceKeyPair = await encryptionService.generateKeyPair();
      final bobKeyPair = await encryptionService.generateKeyPair();
      
      const conversationId = 'dm_alice_bob';
      const message = 'Hello Bob, this is a secret message!';

      // Alice derives conversation key and encrypts message
      final aliceConversationKey = await keyDerivationService.deriveConversationKey(
        conversationId: conversationId,
        conversationType: ConversationType.direct,
        myPrivateKey: aliceKeyPair.privateKey,
        otherPublicKey: bobKeyPair.publicKey,
      );

      final encryptedData = await encryptionService.encryptData(
        Uint8List.fromList(message.codeUnits),
        aliceConversationKey,
      );

      // Bob derives the same conversation key and decrypts message
      final bobConversationKey = await keyDerivationService.deriveConversationKey(
        conversationId: conversationId,
        conversationType: ConversationType.direct,
        myPrivateKey: bobKeyPair.privateKey,
        otherPublicKey: aliceKeyPair.publicKey,
      );

      final decryptedData = await encryptionService.decryptData(
        encryptedData,
        bobConversationKey,
      );

      final decryptedMessage = String.fromCharCodes(decryptedData);

      // Bob should be able to decrypt Alice's message
      expect(decryptedMessage, equals(message));
    });

    test('Security: Different key pairs cannot decrypt each other\'s messages', () async {
      // Setup Alice, Bob, and Charlie (unauthorized third party)
      final aliceKeyPair = await encryptionService.generateKeyPair();
      final bobKeyPair = await encryptionService.generateKeyPair();
      final charlieKeyPair = await encryptionService.generateKeyPair();
      
      const conversationId = 'dm_alice_bob';
      const message = 'Secret message between Alice and Bob';

      // Alice encrypts message for Bob
      final aliceConversationKey = await keyDerivationService.deriveConversationKey(
        conversationId: conversationId,
        conversationType: ConversationType.direct,
        myPrivateKey: aliceKeyPair.privateKey,
        otherPublicKey: bobKeyPair.publicKey,
      );

      final encryptedData = await encryptionService.encryptData(
        Uint8List.fromList(message.codeUnits),
        aliceConversationKey,
      );

      // Charlie tries to derive the conversation key (should fail)
      final charlieConversationKey = await keyDerivationService.deriveConversationKey(
        conversationId: conversationId,
        conversationType: ConversationType.direct,
        myPrivateKey: charlieKeyPair.privateKey,
        otherPublicKey: aliceKeyPair.publicKey, // Charlie doesn't have Bob's key
      );

      // Charlie's key should be different
      expect(charlieConversationKey.symmetricKey, isNot(equals(aliceConversationKey.symmetricKey)));

      // Charlie should not be able to decrypt the message
      expect(() async {
        await encryptionService.decryptData(encryptedData, charlieConversationKey);
      }, throwsA(isA<Exception>()));
    });

    test('Performance: Key derivation completes within acceptable time', () async {
      final aliceKeyPair = await encryptionService.generateKeyPair();
      final bobKeyPair = await encryptionService.generateKeyPair();
      
      const conversationId = 'performance_test';

      final stopwatch = Stopwatch()..start();

      await keyDerivationService.deriveConversationKey(
        conversationId: conversationId,
        conversationType: ConversationType.direct,
        myPrivateKey: aliceKeyPair.privateKey,
        otherPublicKey: bobKeyPair.publicKey,
      );

      stopwatch.stop();

      // Key derivation should complete within 50ms (generous limit for testing)
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });
  });
}
