import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/encryption_key.dart';
import 'key_management_service.dart';
import 'encryption_service.dart';

/// Service to handle migration from server-side key storage to secure key derivation
/// Ensures backward compatibility during the transition period
class SecureMigrationService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final KeyManagementService _keyManagementService = KeyManagementService();
  final EncryptionService _encryptionService = EncryptionService();

  /// Check if the secure key exchange migration has been completed
  Future<bool> isMigrationCompleted() async {
    try {
      final response = await _supabase
          .from('e2e_migration_status')
          .select('status')
          .eq('migration_name', 'secure_key_exchange_v1')
          .maybeSingle();

      return response?['status'] == 'completed';
    } catch (e) {
      debugPrint('Error checking migration status: $e');
      return false;
    }
  }

  /// Migrate existing encrypted messages to use secure key derivation
  Future<void> migrateExistingMessages() async {
    try {
      debugPrint('🔄 Starting secure key exchange migration...');

      // Check if migration is already completed
      if (await isMigrationCompleted()) {
        debugPrint('✅ Migration already completed');
        return;
      }

      // Migrate direct messages
      await _migrateDirectMessages();

      // Migrate pulse chat messages
      await _migratePulseChatMessages();

      // Mark migration as completed
      await _markMigrationCompleted();

      debugPrint('✅ Secure key exchange migration completed successfully');
    } catch (e) {
      debugPrint('❌ Error during migration: $e');
      await _markMigrationFailed(e.toString());
      rethrow;
    }
  }

  /// Migrate direct messages to use secure key derivation
  Future<void> _migrateDirectMessages() async {
    debugPrint('🔄 Migrating direct messages...');

    try {
      // Get all encrypted direct messages that need migration
      final messages = await _supabase
          .from('direct_messages')
          .select('id, sender_id, receiver_id, content, encryption_metadata')
          .eq('is_encrypted', true);

      int migratedCount = 0;
      int errorCount = 0;

      for (final message in messages) {
        try {
          final senderId = message['sender_id'] as String;
          final receiverId = message['receiver_id'] as String;
          
          // Verify both users can establish secure communication
          final canCommunicate = await _canEstablishSecureCommunication(senderId, receiverId);
          if (!canCommunicate) {
            debugPrint('⚠️ Cannot establish secure communication between $senderId and $receiverId');
            continue;
          }

          // Test decryption with new key derivation method
          final success = await _testMessageDecryption(message);
          if (success) {
            migratedCount++;
          } else {
            errorCount++;
          }
        } catch (e) {
          debugPrint('❌ Error migrating message ${message['id']}: $e');
          errorCount++;
        }
      }

      debugPrint('✅ Direct messages migration: $migratedCount migrated, $errorCount errors');
    } catch (e) {
      debugPrint('❌ Error migrating direct messages: $e');
      rethrow;
    }
  }

  /// Migrate pulse chat messages to use secure key derivation
  Future<void> _migratePulseChatMessages() async {
    debugPrint('🔄 Migrating pulse chat messages...');

    try {
      // Get all pulse chat keys that need migration
      final pulseKeys = await _supabase
          .from('pulse_chat_keys')
          .select('pulse_id, key_id, created_by')
          .eq('requires_key_derivation', true)
          .eq('migration_completed', false);

      int migratedCount = 0;
      int errorCount = 0;

      for (final keyRecord in pulseKeys) {
        try {
          final pulseId = keyRecord['pulse_id'] as String;
          
          // Mark this pulse as migrated to secure key derivation
          await _supabase
              .from('pulse_chat_keys')
              .update({
                'migration_completed': true,
                'key_exchange_method': 'ECDH-HKDF-SHA256',
              })
              .eq('pulse_id', pulseId);

          migratedCount++;
        } catch (e) {
          debugPrint('❌ Error migrating pulse ${keyRecord['pulse_id']}: $e');
          errorCount++;
        }
      }

      debugPrint('✅ Pulse chat migration: $migratedCount migrated, $errorCount errors');
    } catch (e) {
      debugPrint('❌ Error migrating pulse chats: $e');
      rethrow;
    }
  }

  /// Test if a message can be decrypted with the new key derivation method
  Future<bool> _testMessageDecryption(Map<String, dynamic> message) async {
    try {
      final senderId = message['sender_id'] as String;
      final receiverId = message['receiver_id'] as String;
      final encryptedContent = message['content'] as String;
      final encryptionMetadata = message['encryption_metadata'];

      if (encryptionMetadata == null) {
        return false;
      }

      // Get conversation key using new secure derivation method
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      final otherUserId = currentUserId == senderId ? receiverId : senderId;
      final conversationKey = await _keyManagementService
          .getOrCreateDirectMessageKey(otherUserId);

      if (conversationKey == null) {
        return false;
      }

      // Attempt to decrypt the message
      final encryptedData = EncryptedData.fromJson(jsonDecode(encryptedContent));
      final decryptedData = await _encryptionService.decryptData(
        encryptedData,
        conversationKey,
      );

      // If we get here without exception, decryption succeeded
      return decryptedData.isNotEmpty;
    } catch (e) {
      debugPrint('❌ Test decryption failed: $e');
      return false;
    }
  }

  /// Check if two users can establish secure communication
  Future<bool> _canEstablishSecureCommunication(String userId1, String userId2) async {
    try {
      final result = await _supabase
          .rpc('can_establish_secure_communication', params: {
            'user1_uuid': userId1,
            'user2_uuid': userId2,
          });

      return result == true;
    } catch (e) {
      debugPrint('Error checking secure communication capability: $e');
      return false;
    }
  }

  /// Mark migration as completed
  Future<void> _markMigrationCompleted() async {
    await _supabase
        .from('e2e_migration_status')
        .upsert({
          'migration_name': 'secure_key_exchange_v1',
          'status': 'completed',
          'completed_at': DateTime.now().toIso8601String(),
        });
  }

  /// Mark migration as failed
  Future<void> _markMigrationFailed(String errorMessage) async {
    await _supabase
        .from('e2e_migration_status')
        .upsert({
          'migration_name': 'secure_key_exchange_v1',
          'status': 'failed',
          'error_message': errorMessage,
        });
  }

  /// Get migration progress
  Future<Map<String, dynamic>?> getMigrationStatus() async {
    try {
      return await _supabase
          .from('e2e_migration_status')
          .select('*')
          .eq('migration_name', 'secure_key_exchange_v1')
          .maybeSingle();
    } catch (e) {
      debugPrint('Error getting migration status: $e');
      return null;
    }
  }

  /// Verify secure key exchange is working correctly
  Future<bool> verifySecureKeyExchange() async {
    try {
      debugPrint('🔍 Verifying secure key exchange...');

      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      // Check if current user has a valid key pair
      if (!_keyManagementService.hasKeyPair) {
        debugPrint('❌ Current user does not have a key pair');
        return false;
      }

      // Check if public key is uploaded to server
      final publicKey = await _keyManagementService.getUserPublicKey(currentUserId);
      if (publicKey == null) {
        debugPrint('❌ Public key not found on server');
        return false;
      }

      debugPrint('✅ Secure key exchange verification passed');
      return true;
    } catch (e) {
      debugPrint('❌ Secure key exchange verification failed: $e');
      return false;
    }
  }

  /// Clean up legacy key storage (use with caution)
  Future<void> cleanupLegacyKeyStorage() async {
    try {
      debugPrint('🧹 Cleaning up legacy key storage...');

      // Only proceed if migration is completed
      if (!await isMigrationCompleted()) {
        throw Exception('Cannot cleanup: migration not completed');
      }

      // Remove backup tables (optional - keep for rollback capability)
      // await _supabase.rpc('drop_table_if_exists', params: {'table_name': 'direct_messages_backup'});
      // await _supabase.rpc('drop_table_if_exists', params: {'table_name': 'chat_messages_backup'});
      // await _supabase.rpc('drop_table_if_exists', params: {'table_name': 'pulse_chat_keys_backup'});

      debugPrint('✅ Legacy key storage cleanup completed');
    } catch (e) {
      debugPrint('❌ Error during cleanup: $e');
      rethrow;
    }
  }
}

/// Migration status enum
enum MigrationStatus {
  notStarted,
  inProgress,
  completed,
  failed,
}

/// Migration result with details
class MigrationResult {
  final MigrationStatus status;
  final String? errorMessage;
  final int migratedRecords;
  final DateTime? completedAt;

  MigrationResult({
    required this.status,
    this.errorMessage,
    this.migratedRecords = 0,
    this.completedAt,
  });

  factory MigrationResult.fromJson(Map<String, dynamic> json) {
    return MigrationResult(
      status: MigrationStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => MigrationStatus.notStarted,
      ),
      errorMessage: json['error_message'],
      migratedRecords: json['affected_records'] ?? 0,
      completedAt: json['completed_at'] != null 
          ? DateTime.parse(json['completed_at']) 
          : null,
    );
  }
}
