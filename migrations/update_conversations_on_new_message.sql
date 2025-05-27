-- Migration: Auto-update conversations table when new messages are sent
-- This ensures real-time conversation list updates with last message preview

-- 1. Create function to update conversation when new message is added
CREATE OR REPLACE FUNCTION update_conversation_on_new_message()
RETURNS TRIGGER AS $$
DECLARE
    message_preview TEXT;
    conversation_id_val UUID;
BEGIN
    -- Get conversation ID based on message type
    IF TG_TABLE_NAME = 'messages' THEN
        conversation_id_val := NEW.conversation_id;
    ELSIF TG_TABLE_NAME = 'direct_messages' THEN
        -- For direct messages, generate conversation ID from sender/receiver
        conversation_id_val := (
            'dm_' || LEAST(NEW.sender_id::text, NEW.receiver_id::text) || 
            '_' || GREATEST(NEW.sender_id::text, NEW.receiver_id::text)
        )::UUID;
    ELSE
        RETURN NEW;
    END IF;

    -- Generate message preview based on message type
    IF NEW.message_type = 'text' THEN
        -- For text messages, use first 100 characters
        message_preview := LEFT(COALESCE(NEW.content, ''), 100);
        IF LENGTH(COALESCE(NEW.content, '')) > 100 THEN
            message_preview := message_preview || '...';
        END IF;
    ELSIF NEW.message_type = 'image' THEN
        message_preview := '📷 Image';
    ELSIF NEW.message_type = 'audio' THEN
        message_preview := '🎵 Voice message';
    ELSIF NEW.message_type = 'file' THEN
        message_preview := '📎 File';
    ELSE
        message_preview := 'Message';
    END IF;

    -- Update the conversations table
    UPDATE conversations 
    SET 
        last_message_at = NEW.created_at,
        updated_at = NEW.created_at,
        -- Store last message preview in metadata for now
        settings = COALESCE(settings, '{}'::jsonb) || 
                  jsonb_build_object('last_message_preview', message_preview)
    WHERE id = conversation_id_val;

    -- If no conversation exists, this might be a new conversation
    -- Log for debugging but don't fail the message insert
    IF NOT FOUND THEN
        RAISE NOTICE 'No conversation found with ID: %', conversation_id_val;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Create triggers for both message tables
DROP TRIGGER IF EXISTS update_conversation_on_new_message_trigger ON messages;
CREATE TRIGGER update_conversation_on_new_message_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_new_message();

DROP TRIGGER IF EXISTS update_conversation_on_new_dm_trigger ON direct_messages;
CREATE TRIGGER update_conversation_on_new_dm_trigger
    AFTER INSERT ON direct_messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_new_message();

-- 3. Add index for better performance on conversations table
CREATE INDEX IF NOT EXISTS idx_conversations_last_message_at 
    ON conversations(last_message_at DESC);

-- 4. Grant necessary permissions
GRANT EXECUTE ON FUNCTION update_conversation_on_new_message() TO authenticated;

-- 5. Add comment for documentation
COMMENT ON FUNCTION update_conversation_on_new_message() IS 
'Automatically updates conversations table with last message info when new messages are inserted';
