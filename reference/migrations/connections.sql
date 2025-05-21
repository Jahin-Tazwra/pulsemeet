-- Create connections table
CREATE TABLE IF NOT EXISTS connections (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  requester_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL CHECK (status IN ('pending', 'accepted', 'declined', 'blocked')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  UNIQUE(requester_id, receiver_id)
);

-- Add comment to table
COMMENT ON TABLE connections IS 'Stores user connections and their status';

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_connections_requester_id ON connections(requester_id);
CREATE INDEX IF NOT EXISTS idx_connections_receiver_id ON connections(receiver_id);
CREATE INDEX IF NOT EXISTS idx_connections_status ON connections(status);

-- Create direct messages table
CREATE TABLE IF NOT EXISTS direct_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  message_type VARCHAR(20) NOT NULL DEFAULT 'text',
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  is_formatted BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  status VARCHAR(20) NOT NULL DEFAULT 'sent',
  media_data JSONB,
  location_data JSONB,
  reply_to_id UUID REFERENCES direct_messages(id) ON DELETE SET NULL,
  edited_at TIMESTAMP WITH TIME ZONE
);

-- Add comment to table
COMMENT ON TABLE direct_messages IS 'Stores direct messages between connected users';

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_direct_messages_sender_id ON direct_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_direct_messages_receiver_id ON direct_messages(receiver_id);
CREATE INDEX IF NOT EXISTS idx_direct_messages_created_at ON direct_messages(created_at);
CREATE INDEX IF NOT EXISTS idx_direct_messages_conversation ON direct_messages(sender_id, receiver_id);

-- Create function to update timestamp
CREATE OR REPLACE FUNCTION update_direct_message_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update timestamp on update
DROP TRIGGER IF EXISTS update_direct_message_timestamp ON direct_messages;
CREATE TRIGGER update_direct_message_timestamp
BEFORE UPDATE ON direct_messages
FOR EACH ROW EXECUTE FUNCTION update_direct_message_timestamp();

-- Create function to update connection timestamp
CREATE OR REPLACE FUNCTION update_connection_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update timestamp on update
DROP TRIGGER IF EXISTS update_connection_timestamp ON connections;
CREATE TRIGGER update_connection_timestamp
BEFORE UPDATE ON connections
FOR EACH ROW EXECUTE FUNCTION update_connection_timestamp();

-- Add RLS policies for connections
ALTER TABLE connections ENABLE ROW LEVEL SECURITY;

-- Policy to allow users to view their own connections
CREATE POLICY "Users can view their own connections"
ON connections FOR SELECT
TO authenticated
USING (requester_id = auth.uid() OR receiver_id = auth.uid());

-- Policy to allow users to create connection requests
CREATE POLICY "Users can create connection requests"
ON connections FOR INSERT
TO authenticated
WITH CHECK (requester_id = auth.uid());

-- Policy to allow users to update their own connections
CREATE POLICY "Users can update their own connections"
ON connections FOR UPDATE
TO authenticated
USING (requester_id = auth.uid() OR receiver_id = auth.uid());

-- Add RLS policies for direct messages
ALTER TABLE direct_messages ENABLE ROW LEVEL SECURITY;

-- Policy to allow users to view their own direct messages
CREATE POLICY "Users can view their own direct messages"
ON direct_messages FOR SELECT
TO authenticated
USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- Policy to allow users to send direct messages
CREATE POLICY "Users can send direct messages"
ON direct_messages FOR INSERT
TO authenticated
WITH CHECK (
  sender_id = auth.uid() AND
  EXISTS (
    SELECT 1 FROM connections
    WHERE (
      (requester_id = auth.uid() AND receiver_id = direct_messages.receiver_id) OR
      (receiver_id = auth.uid() AND requester_id = direct_messages.receiver_id)
    ) AND status = 'accepted'
  )
);

-- Policy to allow users to update their own messages
CREATE POLICY "Users can update their own direct messages"
ON direct_messages FOR UPDATE
TO authenticated
USING (sender_id = auth.uid());

-- Policy to allow users to delete their own messages
CREATE POLICY "Users can delete their own direct messages"
ON direct_messages FOR DELETE
TO authenticated
USING (sender_id = auth.uid());

-- Create direct_message_typing_status table
CREATE TABLE IF NOT EXISTS direct_message_typing_status (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  is_typing BOOLEAN NOT NULL DEFAULT false,
  last_updated TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, receiver_id)
);

-- Add comment to table
COMMENT ON TABLE direct_message_typing_status IS 'Tracks user typing status in direct messages';

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_dm_typing_status_user_id ON direct_message_typing_status(user_id);
CREATE INDEX IF NOT EXISTS idx_dm_typing_status_receiver_id ON direct_message_typing_status(receiver_id);
CREATE INDEX IF NOT EXISTS idx_dm_typing_status_is_typing ON direct_message_typing_status(is_typing);

-- Create function to update typing status timestamp
CREATE OR REPLACE FUNCTION update_dm_typing_status_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.last_updated = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update timestamp on update
DROP TRIGGER IF EXISTS update_dm_typing_status_timestamp ON direct_message_typing_status;
CREATE TRIGGER update_dm_typing_status_timestamp
BEFORE UPDATE ON direct_message_typing_status
FOR EACH ROW EXECUTE FUNCTION update_dm_typing_status_timestamp();

-- Create function to clean up old typing statuses
CREATE OR REPLACE FUNCTION cleanup_dm_typing_status()
RETURNS TRIGGER AS $$
BEGIN
  -- Delete typing statuses older than 30 seconds
  DELETE FROM direct_message_typing_status
  WHERE last_updated < NOW() - INTERVAL '30 seconds'
  AND is_typing = true;
  
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to clean up old typing statuses
DROP TRIGGER IF EXISTS cleanup_dm_typing_status_trigger ON direct_message_typing_status;
CREATE TRIGGER cleanup_dm_typing_status_trigger
AFTER INSERT OR UPDATE ON direct_message_typing_status
FOR EACH STATEMENT EXECUTE FUNCTION cleanup_dm_typing_status();

-- Add RLS policies for direct message typing status
ALTER TABLE direct_message_typing_status ENABLE ROW LEVEL SECURITY;

-- Policy to allow users to view typing status for their conversations
CREATE POLICY "Users can view typing status for their conversations"
ON direct_message_typing_status FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR receiver_id = auth.uid());

-- Policy to allow users to insert their own typing status
CREATE POLICY "Users can insert their own typing status"
ON direct_message_typing_status FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Policy to allow users to update their own typing status
CREATE POLICY "Users can update their own typing status"
ON direct_message_typing_status FOR UPDATE
TO authenticated
USING (user_id = auth.uid());
