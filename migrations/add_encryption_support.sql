-- Migration to add end-to-end encryption support to PulseMeet
-- This adds encryption metadata and public key storage

-- 1. Create user public keys table
CREATE TABLE IF NOT EXISTS user_public_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    key_id VARCHAR(255) NOT NULL,
    public_key TEXT NOT NULL,
    algorithm VARCHAR(50) NOT NULL DEFAULT 'x25519',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN NOT NULL DEFAULT true,
    
    -- Ensure unique active key per user
    UNIQUE(user_id, key_id),
    
    -- Index for efficient lookups
    INDEX idx_user_public_keys_user_id ON user_public_keys(user_id),
    INDEX idx_user_public_keys_active ON user_public_keys(user_id, is_active)
);

-- 2. Add encryption metadata to direct_messages table
ALTER TABLE direct_messages 
ADD COLUMN IF NOT EXISTS is_encrypted BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS encryption_metadata JSONB,
ADD COLUMN IF NOT EXISTS key_version INTEGER DEFAULT 1;

-- 3. Add encryption metadata to chat_messages table  
ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS is_encrypted BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS encryption_metadata JSONB,
ADD COLUMN IF NOT EXISTS key_version INTEGER DEFAULT 1;

-- 4. Create conversation keys table for group chat key management
CREATE TABLE IF NOT EXISTS conversation_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id VARCHAR(255) NOT NULL,
    conversation_type VARCHAR(20) NOT NULL CHECK (conversation_type IN ('direct', 'pulse')),
    key_id VARCHAR(255) NOT NULL,
    encrypted_key TEXT NOT NULL, -- Encrypted with user's public key
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE,
    version INTEGER NOT NULL DEFAULT 1,
    is_active BOOLEAN NOT NULL DEFAULT true,
    
    -- Ensure unique key per conversation per user
    UNIQUE(conversation_id, user_id, version),
    
    -- Indexes for efficient lookups
    INDEX idx_conversation_keys_conversation ON conversation_keys(conversation_id, conversation_type),
    INDEX idx_conversation_keys_user ON conversation_keys(user_id, is_active)
);

-- 5. Create key exchange requests table for secure key distribution
CREATE TABLE IF NOT EXISTS key_exchange_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    target_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    conversation_id VARCHAR(255) NOT NULL,
    conversation_type VARCHAR(20) NOT NULL CHECK (conversation_type IN ('direct', 'pulse')),
    encrypted_key TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'expired')),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
    
    -- Ensure unique request per conversation per user pair
    UNIQUE(requester_id, target_id, conversation_id),
    
    -- Indexes
    INDEX idx_key_exchange_target ON key_exchange_requests(target_id, status),
    INDEX idx_key_exchange_conversation ON key_exchange_requests(conversation_id, status)
);

-- 6. Add RLS policies for user_public_keys
ALTER TABLE user_public_keys ENABLE ROW LEVEL SECURITY;

-- Users can read all public keys (they're public!)
CREATE POLICY "Public keys are readable by all authenticated users" ON user_public_keys
    FOR SELECT TO authenticated
    USING (true);

-- Users can only insert/update their own public keys
CREATE POLICY "Users can manage their own public keys" ON user_public_keys
    FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 7. Add RLS policies for conversation_keys
ALTER TABLE conversation_keys ENABLE ROW LEVEL SECURITY;

-- Users can only access their own conversation keys
CREATE POLICY "Users can access their own conversation keys" ON conversation_keys
    FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 8. Add RLS policies for key_exchange_requests
ALTER TABLE key_exchange_requests ENABLE ROW LEVEL SECURITY;

-- Users can see requests they sent or received
CREATE POLICY "Users can see their key exchange requests" ON key_exchange_requests
    FOR SELECT TO authenticated
    USING (auth.uid() = requester_id OR auth.uid() = target_id);

-- Users can create requests
CREATE POLICY "Users can create key exchange requests" ON key_exchange_requests
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = requester_id);

-- Users can update requests they received
CREATE POLICY "Users can update received key exchange requests" ON key_exchange_requests
    FOR UPDATE TO authenticated
    USING (auth.uid() = target_id)
    WITH CHECK (auth.uid() = target_id);

-- 9. Create function to automatically expire old key exchange requests
CREATE OR REPLACE FUNCTION expire_old_key_exchange_requests()
RETURNS void AS $$
BEGIN
    UPDATE key_exchange_requests 
    SET status = 'expired'
    WHERE status = 'pending' 
    AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- 10. Create function to clean up old inactive keys
CREATE OR REPLACE FUNCTION cleanup_old_encryption_keys()
RETURNS void AS $$
BEGIN
    -- Deactivate expired user public keys
    UPDATE user_public_keys 
    SET is_active = false
    WHERE is_active = true 
    AND expires_at IS NOT NULL 
    AND expires_at < NOW();
    
    -- Deactivate expired conversation keys
    UPDATE conversation_keys 
    SET is_active = false
    WHERE is_active = true 
    AND expires_at IS NOT NULL 
    AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- 11. Add indexes for better performance on encrypted message queries
CREATE INDEX IF NOT EXISTS idx_direct_messages_encrypted ON direct_messages(is_encrypted, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_messages_encrypted ON chat_messages(is_encrypted, created_at);

-- 12. Add function to get conversation participants for key distribution
CREATE OR REPLACE FUNCTION get_conversation_participants(
    conv_id TEXT,
    conv_type TEXT
)
RETURNS TABLE(user_id UUID) AS $$
BEGIN
    IF conv_type = 'direct' THEN
        -- For direct messages, extract user IDs from conversation ID
        -- Format: dm_uuid1_uuid2
        RETURN QUERY
        SELECT UNNEST(ARRAY[
            SUBSTRING(conv_id FROM 4 FOR 36)::UUID,
            SUBSTRING(conv_id FROM 41 FOR 36)::UUID
        ]);
    ELSIF conv_type = 'pulse' THEN
        -- For pulse chats, get all participants
        RETURN QUERY
        SELECT pp.user_id
        FROM pulse_participants pp
        WHERE pp.pulse_id = conv_id::UUID
        AND pp.status = 'joined';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 13. Create notification function for new encrypted messages
CREATE OR REPLACE FUNCTION notify_encrypted_message()
RETURNS trigger AS $$
BEGIN
    -- Only notify for encrypted messages
    IF NEW.is_encrypted = true THEN
        PERFORM pg_notify(
            'encrypted_message',
            json_build_object(
                'table', TG_TABLE_NAME,
                'id', NEW.id,
                'sender_id', NEW.sender_id,
                'conversation_id', CASE 
                    WHEN TG_TABLE_NAME = 'direct_messages' THEN 
                        'dm_' || LEAST(NEW.sender_id::text, NEW.receiver_id::text) || '_' || GREATEST(NEW.sender_id::text, NEW.receiver_id::text)
                    ELSE NEW.pulse_id::text
                END,
                'created_at', NEW.created_at
            )::text
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 14. Create triggers for encrypted message notifications
DROP TRIGGER IF EXISTS encrypted_direct_message_notify ON direct_messages;
CREATE TRIGGER encrypted_direct_message_notify
    AFTER INSERT ON direct_messages
    FOR EACH ROW
    EXECUTE FUNCTION notify_encrypted_message();

DROP TRIGGER IF EXISTS encrypted_chat_message_notify ON chat_messages;
CREATE TRIGGER encrypted_chat_message_notify
    AFTER INSERT ON chat_messages
    FOR EACH ROW
    EXECUTE FUNCTION notify_encrypted_message();

-- 15. Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
