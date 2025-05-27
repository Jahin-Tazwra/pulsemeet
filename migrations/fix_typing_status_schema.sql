-- Fix typing status schema to support unified conversation system
-- This migration creates the correct typing_status table that the ConversationService expects

-- 1. Create the unified typing_status table
CREATE TABLE IF NOT EXISTS typing_status (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    is_typing BOOLEAN NOT NULL DEFAULT false,
    last_updated TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    -- Unique constraint for conversation_id and user_id combination
    CONSTRAINT typing_status_conversation_id_user_id_key UNIQUE(conversation_id, user_id)
);

-- Add comment to table
COMMENT ON TABLE typing_status IS 'Tracks user typing status in conversations (both pulse chats and direct messages)';

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_typing_status_conversation_id ON typing_status(conversation_id);
CREATE INDEX IF NOT EXISTS idx_typing_status_user_id ON typing_status(user_id);
CREATE INDEX IF NOT EXISTS idx_typing_status_is_typing ON typing_status(is_typing);
CREATE INDEX IF NOT EXISTS idx_typing_status_last_updated ON typing_status(last_updated);

-- Create function to automatically update last_updated timestamp
CREATE OR REPLACE FUNCTION update_typing_status_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_updated = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update timestamp on update
DROP TRIGGER IF EXISTS update_typing_status_timestamp ON typing_status;
CREATE TRIGGER update_typing_status_timestamp
    BEFORE UPDATE ON typing_status
    FOR EACH ROW EXECUTE FUNCTION update_typing_status_timestamp();

-- Create function to automatically clean up old typing statuses
CREATE OR REPLACE FUNCTION cleanup_old_typing_status()
RETURNS TRIGGER AS $$
BEGIN
    -- Delete typing statuses older than 30 seconds where user stopped typing
    DELETE FROM typing_status
    WHERE last_updated < NOW() - INTERVAL '30 seconds'
    AND is_typing = false;
    
    -- Reset typing status to false for entries older than 10 seconds that are still marked as typing
    UPDATE typing_status
    SET is_typing = false, last_updated = NOW()
    WHERE last_updated < NOW() - INTERVAL '10 seconds'
    AND is_typing = true;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to clean up old typing statuses
DROP TRIGGER IF EXISTS cleanup_old_typing_status_trigger ON typing_status;
CREATE TRIGGER cleanup_old_typing_status_trigger
    AFTER INSERT OR UPDATE ON typing_status
    FOR EACH STATEMENT EXECUTE FUNCTION cleanup_old_typing_status();

-- Enable RLS
ALTER TABLE typing_status ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can view typing status for conversations they participate in
DROP POLICY IF EXISTS "Users can view typing status for their conversations" ON typing_status;
CREATE POLICY "Users can view typing status for their conversations"
ON typing_status FOR SELECT
TO authenticated
USING (
    -- Check if user is a participant in the conversation
    EXISTS (
        SELECT 1 FROM conversation_participants cp
        WHERE cp.conversation_id = typing_status.conversation_id
        AND cp.user_id = auth.uid()
    )
);

-- RLS Policy: Users can insert their own typing status
DROP POLICY IF EXISTS "Users can insert their own typing status" ON typing_status;
CREATE POLICY "Users can insert their own typing status"
ON typing_status FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- RLS Policy: Users can update their own typing status
DROP POLICY IF EXISTS "Users can update their own typing status" ON typing_status;
CREATE POLICY "Users can update their own typing status"
ON typing_status FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- RLS Policy: Users can delete their own typing status
DROP POLICY IF EXISTS "Users can delete their own typing status" ON typing_status;
CREATE POLICY "Users can delete their own typing status"
ON typing_status FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- Create a function to migrate data from existing typing status tables (if needed)
CREATE OR REPLACE FUNCTION migrate_existing_typing_status()
RETURNS void AS $$
BEGIN
    -- Migrate from pulse_typing_status if it exists
    INSERT INTO typing_status (conversation_id, user_id, is_typing, last_updated)
    SELECT 
        pts.pulse_id::text::uuid as conversation_id,
        pts.user_id,
        pts.is_typing,
        pts.last_updated
    FROM pulse_typing_status pts
    WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'pulse_typing_status')
    ON CONFLICT (conversation_id, user_id) DO UPDATE SET
        is_typing = EXCLUDED.is_typing,
        last_updated = EXCLUDED.last_updated;
        
    -- Note: direct_message_typing_status uses a different schema (user_id, receiver_id)
    -- and would need conversation_id mapping, so we'll handle that separately if needed
    
    RAISE NOTICE 'Typing status migration completed';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Typing status migration failed or not needed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- Run the migration (this will only work if the source tables exist)
SELECT migrate_existing_typing_status();
