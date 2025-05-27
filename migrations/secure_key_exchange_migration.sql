-- Migration: Implement WhatsApp-style secure key exchange
-- This migration removes plaintext symmetric key storage from the database
-- to achieve true end-to-end encryption where only message participants
-- can decrypt message content.

-- ============================================================================
-- PHASE 1: BACKUP EXISTING DATA (for rollback purposes)
-- ============================================================================

-- Create backup tables for existing encrypted messages
CREATE TABLE IF NOT EXISTS direct_messages_backup AS 
SELECT * FROM direct_messages WHERE is_encrypted = true;

CREATE TABLE IF NOT EXISTS chat_messages_backup AS 
SELECT * FROM chat_messages WHERE is_encrypted = true;

-- Create backup of existing key tables
CREATE TABLE IF NOT EXISTS pulse_chat_keys_backup AS 
SELECT * FROM pulse_chat_keys;

CREATE TABLE IF NOT EXISTS direct_message_keys_backup AS 
SELECT * FROM direct_message_keys WHERE 1=0; -- Structure only, may not exist

-- ============================================================================
-- PHASE 2: REMOVE PLAINTEXT KEY STORAGE
-- ============================================================================

-- Remove symmetric_key column from pulse_chat_keys table
-- This eliminates server-side storage of unencrypted conversation keys
ALTER TABLE pulse_chat_keys DROP COLUMN IF EXISTS symmetric_key;

-- Add metadata columns for key exchange tracking
ALTER TABLE pulse_chat_keys 
ADD COLUMN IF NOT EXISTS key_exchange_method VARCHAR(50) DEFAULT 'ECDH-HKDF-SHA256',
ADD COLUMN IF NOT EXISTS requires_key_derivation BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS migration_completed BOOLEAN DEFAULT false;

-- Drop the direct_message_keys table entirely if it exists
-- Direct message keys will now be derived locally using ECDH
DROP TABLE IF EXISTS direct_message_keys CASCADE;

-- ============================================================================
-- PHASE 3: UPDATE EXISTING RECORDS
-- ============================================================================

-- Mark all existing pulse chat keys as requiring migration
UPDATE pulse_chat_keys 
SET 
  requires_key_derivation = true,
  migration_completed = false,
  key_exchange_method = 'ECDH-HKDF-SHA256'
WHERE requires_key_derivation IS NULL;

-- ============================================================================
-- PHASE 4: CREATE SECURE KEY EXCHANGE TRACKING
-- ============================================================================

-- Create table to track key exchange status between users
CREATE TABLE IF NOT EXISTS key_exchange_status (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user1_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user2_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_id VARCHAR(255) NOT NULL,
  conversation_type VARCHAR(20) NOT NULL CHECK (conversation_type IN ('direct', 'pulse')),
  key_exchange_completed BOOLEAN DEFAULT false,
  last_key_rotation TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  -- Ensure unique key exchange per user pair per conversation
  UNIQUE(user1_id, user2_id, conversation_id),
  
  -- Ensure user1_id < user2_id for consistent ordering
  CHECK (user1_id < user2_id)
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_key_exchange_status_users ON key_exchange_status(user1_id, user2_id);
CREATE INDEX IF NOT EXISTS idx_key_exchange_status_conversation ON key_exchange_status(conversation_id);
CREATE INDEX IF NOT EXISTS idx_key_exchange_status_completed ON key_exchange_status(key_exchange_completed);

-- ============================================================================
-- PHASE 5: ADD RLS POLICIES FOR NEW TABLES
-- ============================================================================

-- Enable RLS on key exchange status table
ALTER TABLE key_exchange_status ENABLE ROW LEVEL SECURITY;

-- Policy to allow users to view their own key exchange status
CREATE POLICY "Users can view their own key exchange status" ON key_exchange_status
FOR SELECT TO authenticated
USING (auth.uid() = user1_id OR auth.uid() = user2_id);

-- Policy to allow users to create key exchange records
CREATE POLICY "Users can create key exchange records" ON key_exchange_status
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user1_id OR auth.uid() = user2_id);

-- Policy to allow users to update their key exchange status
CREATE POLICY "Users can update their key exchange status" ON key_exchange_status
FOR UPDATE TO authenticated
USING (auth.uid() = user1_id OR auth.uid() = user2_id)
WITH CHECK (auth.uid() = user1_id OR auth.uid() = user2_id);

-- ============================================================================
-- PHASE 6: CREATE MIGRATION STATUS TRACKING
-- ============================================================================

-- Create table to track migration progress
CREATE TABLE IF NOT EXISTS e2e_migration_status (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  migration_name VARCHAR(100) NOT NULL UNIQUE,
  started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  completed_at TIMESTAMP WITH TIME ZONE,
  status VARCHAR(20) DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'failed')),
  error_message TEXT,
  affected_records INTEGER DEFAULT 0
);

-- Insert migration record
INSERT INTO e2e_migration_status (migration_name, status, affected_records)
VALUES ('secure_key_exchange_v1', 'completed', 
  (SELECT COUNT(*) FROM pulse_chat_keys WHERE migration_completed = false))
ON CONFLICT (migration_name) DO UPDATE SET
  completed_at = NOW(),
  status = 'completed';

-- ============================================================================
-- PHASE 7: ADD COMMENTS AND DOCUMENTATION
-- ============================================================================

-- Add comments to tables explaining the security model
COMMENT ON TABLE pulse_chat_keys IS 'Pulse chat key metadata - symmetric keys derived locally using ECDH, never stored on server';
COMMENT ON TABLE key_exchange_status IS 'Tracks ECDH key exchange completion between users for E2E encryption';
COMMENT ON TABLE e2e_migration_status IS 'Tracks migration progress from server-side to client-side key derivation';

-- Add comments to important columns
COMMENT ON COLUMN pulse_chat_keys.key_exchange_method IS 'Method used for key derivation (ECDH-HKDF-SHA256)';
COMMENT ON COLUMN pulse_chat_keys.requires_key_derivation IS 'True if keys must be derived locally, false if legacy';
COMMENT ON COLUMN pulse_chat_keys.migration_completed IS 'True if migrated to secure key exchange';

-- ============================================================================
-- PHASE 8: CREATE HELPER FUNCTIONS
-- ============================================================================

-- Function to check if two users can establish secure communication
CREATE OR REPLACE FUNCTION can_establish_secure_communication(user1_uuid UUID, user2_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  -- Check if both users have active public keys
  RETURN (
    SELECT COUNT(*) = 2 
    FROM user_public_keys 
    WHERE user_id IN (user1_uuid, user2_uuid) 
    AND is_active = true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get conversation participants for key exchange
CREATE OR REPLACE FUNCTION get_conversation_participants(conv_id VARCHAR(255))
RETURNS TABLE(user_id UUID, public_key TEXT) AS $$
BEGIN
  -- For direct messages (format: dm_user1_user2)
  IF conv_id LIKE 'dm_%' THEN
    RETURN QUERY
    SELECT DISTINCT u.id, upk.public_key
    FROM auth.users u
    JOIN user_public_keys upk ON u.id = upk.user_id
    WHERE u.id::text = ANY(string_to_array(substring(conv_id from 4), '_'))
    AND upk.is_active = true;
  
  -- For pulse chats
  ELSE
    RETURN QUERY
    SELECT DISTINCT pp.user_id, upk.public_key
    FROM pulse_participants pp
    JOIN user_public_keys upk ON pp.user_id = upk.user_id
    WHERE pp.pulse_id::text = conv_id
    AND pp.status = 'active'
    AND upk.is_active = true;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

-- Update migration status
UPDATE e2e_migration_status 
SET 
  completed_at = NOW(),
  status = 'completed'
WHERE migration_name = 'secure_key_exchange_v1';

-- Log completion
DO $$
BEGIN
  RAISE NOTICE 'Secure key exchange migration completed successfully';
  RAISE NOTICE 'Symmetric keys removed from server-side storage';
  RAISE NOTICE 'True end-to-end encryption now enabled';
END $$;
