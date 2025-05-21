-- Add status field to pulses table
ALTER TABLE pulses ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'Open';

-- Create pulse_waiting_list table
CREATE TABLE IF NOT EXISTS pulse_waiting_list (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  pulse_id UUID NOT NULL REFERENCES pulses(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  position INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'Waiting', -- Waiting, Promoted, Removed
  UNIQUE(pulse_id, user_id)
);

-- Create index on pulse_waiting_list
CREATE INDEX IF NOT EXISTS idx_pulse_waiting_list_pulse_id ON pulse_waiting_list(pulse_id);
CREATE INDEX IF NOT EXISTS idx_pulse_waiting_list_user_id ON pulse_waiting_list(user_id);
CREATE INDEX IF NOT EXISTS idx_pulse_waiting_list_position ON pulse_waiting_list(pulse_id, position);

-- Create function to check and update pulse status based on participant count
CREATE OR REPLACE FUNCTION check_pulse_capacity() RETURNS TRIGGER AS $$
DECLARE
  participant_count INTEGER;
  max_participants INTEGER;
BEGIN
  -- Get the current participant count and max participants for the pulse
  SELECT COUNT(*) INTO participant_count
  FROM pulse_participants
  WHERE pulse_id = NEW.pulse_id AND status = 'active';

  SELECT p.max_participants INTO max_participants
  FROM pulses p
  WHERE p.id = NEW.pulse_id;

  -- Update pulse status if needed
  IF max_participants IS NOT NULL AND participant_count >= max_participants THEN
    UPDATE pulses SET status = 'Full' WHERE id = NEW.pulse_id;
  ELSE
    UPDATE pulses SET status = 'Open' WHERE id = NEW.pulse_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to check capacity when participants change
DROP TRIGGER IF EXISTS check_pulse_capacity_trigger ON pulse_participants;
CREATE TRIGGER check_pulse_capacity_trigger
AFTER INSERT OR UPDATE OR DELETE ON pulse_participants
FOR EACH ROW EXECUTE FUNCTION check_pulse_capacity();

-- Create function to manage waiting list when a participant leaves
CREATE OR REPLACE FUNCTION manage_waiting_list() RETURNS TRIGGER AS $$
DECLARE
  max_participants INTEGER;
  current_participants INTEGER;
  next_waiting_user UUID;
  next_waiting_entry UUID;
BEGIN
  -- Only proceed if a participant has left
  IF (TG_OP = 'UPDATE' AND NEW.status = 'left') OR (TG_OP = 'DELETE') THEN
    -- Get the pulse's max participants
    SELECT p.max_participants INTO max_participants
    FROM pulses p
    WHERE p.id = CASE WHEN TG_OP = 'DELETE' THEN OLD.pulse_id ELSE NEW.pulse_id END;

    -- If there's no max, we don't need to manage a waiting list
    IF max_participants IS NULL THEN
      RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    -- Get current participant count
    SELECT COUNT(*) INTO current_participants
    FROM pulse_participants
    WHERE pulse_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.pulse_id ELSE NEW.pulse_id END
    AND status = 'active';

    -- If we're below max capacity, promote someone from the waiting list
    IF current_participants < max_participants THEN
      -- Find the next person on the waiting list
      SELECT wl.user_id, wl.id INTO next_waiting_user, next_waiting_entry
      FROM pulse_waiting_list wl
      WHERE wl.pulse_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.pulse_id ELSE NEW.pulse_id END
      AND wl.status = 'Waiting'
      ORDER BY wl.position ASC
      LIMIT 1;

      -- If there's someone waiting, add them to participants
      IF next_waiting_user IS NOT NULL THEN
        -- Add to participants
        INSERT INTO pulse_participants (pulse_id, user_id, status, joined_at)
        VALUES (
          CASE WHEN TG_OP = 'DELETE' THEN OLD.pulse_id ELSE NEW.pulse_id END,
          next_waiting_user,
          'active',
          NOW()
        );

        -- Update waiting list entry status
        UPDATE pulse_waiting_list
        SET status = 'Promoted'
        WHERE id = next_waiting_entry;

        -- Reorder remaining waiting list entries
        WITH waiting_entry AS (
          SELECT position FROM pulse_waiting_list WHERE id = next_waiting_entry
        )
        UPDATE pulse_waiting_list
        SET position = position - 1
        WHERE pulse_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.pulse_id ELSE NEW.pulse_id END
        AND status = 'Waiting'
        AND position > (SELECT position FROM waiting_entry);
      END IF;
    END IF;
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to manage waiting list when participants change
DROP TRIGGER IF EXISTS manage_waiting_list_trigger ON pulse_participants;
CREATE TRIGGER manage_waiting_list_trigger
AFTER UPDATE OR DELETE ON pulse_participants
FOR EACH ROW EXECUTE FUNCTION manage_waiting_list();

-- Create function to get next position in waiting list
CREATE OR REPLACE FUNCTION get_next_waiting_list_position(pulse_id_param UUID)
RETURNS INTEGER AS $$
DECLARE
  next_position INTEGER;
BEGIN
  SELECT COALESCE(MAX(position), 0) + 1 INTO next_position
  FROM pulse_waiting_list
  WHERE pulse_id = pulse_id_param AND status = 'Waiting';

  RETURN next_position;
END;
$$ LANGUAGE plpgsql;

-- Add RLS policies for pulse_waiting_list
ALTER TABLE pulse_waiting_list ENABLE ROW LEVEL SECURITY;

-- Policy to allow users to view waiting lists for pulses they're involved with
CREATE POLICY "Users can view waiting lists for pulses they're involved with"
ON pulse_waiting_list FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM pulse_participants
    WHERE pulse_participants.pulse_id = pulse_waiting_list.pulse_id
    AND pulse_participants.user_id = auth.uid()
  ) OR
  EXISTS (
    SELECT 1 FROM pulses
    WHERE pulses.id = pulse_waiting_list.pulse_id
    AND pulses.creator_id = auth.uid()
  )
);

-- Policy to allow users to join waiting lists
CREATE POLICY "Users can join waiting lists"
ON pulse_waiting_list FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Policy to allow users to leave waiting lists
CREATE POLICY "Users can leave waiting lists"
ON pulse_waiting_list FOR DELETE
TO authenticated
USING (user_id = auth.uid());
