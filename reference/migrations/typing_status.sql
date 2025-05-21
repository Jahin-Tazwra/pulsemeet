-- Create pulse_typing_status table
CREATE TABLE IF NOT EXISTS pulse_typing_status (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  pulse_id UUID NOT NULL REFERENCES pulses(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  is_typing BOOLEAN NOT NULL DEFAULT false,
  last_updated TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  UNIQUE(pulse_id, user_id)
);

-- Add comment to table
COMMENT ON TABLE pulse_typing_status IS 'Tracks user typing status in pulse chats';

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_typing_status_pulse_id ON pulse_typing_status(pulse_id);
CREATE INDEX IF NOT EXISTS idx_typing_status_user_id ON pulse_typing_status(user_id);
CREATE INDEX IF NOT EXISTS idx_typing_status_is_typing ON pulse_typing_status(is_typing);

-- Create function to automatically update last_updated timestamp
CREATE OR REPLACE FUNCTION update_typing_status_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.last_updated = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update timestamp on update
DROP TRIGGER IF EXISTS update_typing_status_timestamp ON pulse_typing_status;
CREATE TRIGGER update_typing_status_timestamp
BEFORE UPDATE ON pulse_typing_status
FOR EACH ROW EXECUTE FUNCTION update_typing_status_timestamp();

-- Create function to automatically clean up old typing statuses
CREATE OR REPLACE FUNCTION cleanup_typing_status()
RETURNS TRIGGER AS $$
BEGIN
  -- Delete typing statuses older than 30 seconds
  DELETE FROM pulse_typing_status
  WHERE last_updated < NOW() - INTERVAL '30 seconds'
  AND is_typing = true;
  
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to clean up old typing statuses
DROP TRIGGER IF EXISTS cleanup_typing_status_trigger ON pulse_typing_status;
CREATE TRIGGER cleanup_typing_status_trigger
AFTER INSERT OR UPDATE ON pulse_typing_status
FOR EACH STATEMENT EXECUTE FUNCTION cleanup_typing_status();

-- Add RLS policies
ALTER TABLE pulse_typing_status ENABLE ROW LEVEL SECURITY;

-- Policy to allow users to view typing status for pulses they're involved with
CREATE POLICY "Users can view typing status for pulses they're involved with"
ON pulse_typing_status FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM pulse_participants
    WHERE pulse_participants.pulse_id = pulse_typing_status.pulse_id
    AND pulse_participants.user_id = auth.uid()
    AND pulse_participants.status = 'active'
  ) OR
  EXISTS (
    SELECT 1 FROM pulses
    WHERE pulses.id = pulse_typing_status.pulse_id
    AND pulses.creator_id = auth.uid()
  )
);

-- Policy to allow users to update their own typing status
CREATE POLICY "Users can update their own typing status"
ON pulse_typing_status FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Policy to allow users to update their own typing status
CREATE POLICY "Users can update their own typing status"
ON pulse_typing_status FOR UPDATE
TO authenticated
USING (user_id = auth.uid());

-- Policy to allow users to delete their own typing status
CREATE POLICY "Users can delete their own typing status"
ON pulse_typing_status FOR DELETE
TO authenticated
USING (user_id = auth.uid());
