-- Add share_code and share_url fields to pulses table
ALTER TABLE pulses ADD COLUMN IF NOT EXISTS share_code TEXT UNIQUE;
ALTER TABLE pulses ADD COLUMN IF NOT EXISTS share_url TEXT;

-- Create index on share_code for faster lookups
CREATE INDEX IF NOT EXISTS idx_pulses_share_code ON pulses(share_code);

-- Function to generate a random alphanumeric code of specified length
CREATE OR REPLACE FUNCTION generate_random_code(length INTEGER)
RETURNS TEXT AS $$
DECLARE
  chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- Excluding similar looking characters (I, 1, O, 0)
  result TEXT := '';
  i INTEGER := 0;
  pos INTEGER;
BEGIN
  FOR i IN 1..length LOOP
    pos := 1 + FLOOR(RANDOM() * LENGTH(chars));
    result := result || SUBSTRING(chars FROM pos FOR 1);
  END LOOP;
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function to generate a unique share code for a pulse
CREATE OR REPLACE FUNCTION generate_unique_pulse_code(code_length INTEGER DEFAULT 6)
RETURNS TEXT AS $$
DECLARE
  new_code TEXT;
  code_exists BOOLEAN;
BEGIN
  LOOP
    -- Generate a random code
    new_code := generate_random_code(code_length);
    
    -- Check if the code already exists
    SELECT EXISTS(SELECT 1 FROM pulses WHERE share_code = new_code) INTO code_exists;
    
    -- If the code doesn't exist, return it
    IF NOT code_exists THEN
      RETURN new_code;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function to generate a share URL for a pulse
CREATE OR REPLACE FUNCTION generate_pulse_share_url(pulse_id UUID, share_code TEXT)
RETURNS TEXT AS $$
BEGIN
  RETURN 'https://pulsemeet.app/pulse/' || share_code;
END;
$$ LANGUAGE plpgsql;

-- Update existing pulses with share codes and URLs
DO $$
DECLARE
  pulse_record RECORD;
  new_code TEXT;
  new_url TEXT;
BEGIN
  FOR pulse_record IN SELECT id FROM pulses WHERE share_code IS NULL LOOP
    -- Generate a unique code
    new_code := generate_unique_pulse_code();
    
    -- Generate a share URL
    new_url := generate_pulse_share_url(pulse_record.id, new_code);
    
    -- Update the pulse
    UPDATE pulses 
    SET share_code = new_code, share_url = new_url
    WHERE id = pulse_record.id;
  END LOOP;
END $$;

-- Modify the create_pulse_with_location function to include share code generation
CREATE OR REPLACE FUNCTION create_pulse_with_location(
  creator_id_param UUID,
  title_param TEXT,
  description_param TEXT,
  activity_emoji_param TEXT,
  latitude_param DOUBLE PRECISION,
  longitude_param DOUBLE PRECISION,
  radius_param INTEGER,
  start_time_param TIMESTAMP WITH TIME ZONE,
  end_time_param TIMESTAMP WITH TIME ZONE,
  max_participants_param INTEGER
) RETURNS UUID AS $$
DECLARE
  new_pulse_id UUID;
  share_code_value TEXT;
  share_url_value TEXT;
BEGIN
  -- Generate a unique share code
  share_code_value := generate_unique_pulse_code();
  
  -- Insert the new pulse
  INSERT INTO pulses (
    creator_id, title, description, activity_emoji,
    location, radius, start_time, end_time,
    max_participants, is_active, share_code, created_at, updated_at
  ) VALUES (
    creator_id_param, title_param, description_param, activity_emoji_param,
    ST_SetSRID(ST_MakePoint(longitude_param, latitude_param), 4326)::geography, radius_param,
    start_time_param, end_time_param,
    max_participants_param, true, share_code_value, NOW(), NOW()
  ) RETURNING id INTO new_pulse_id;
  
  -- Generate and update the share URL
  share_url_value := generate_pulse_share_url(new_pulse_id, share_code_value);
  UPDATE pulses SET share_url = share_url_value WHERE id = new_pulse_id;
  
  -- Return the new pulse ID
  RETURN new_pulse_id;
END;
$$ LANGUAGE plpgsql;

-- Create a function to find a pulse by share code
CREATE OR REPLACE FUNCTION find_pulse_by_share_code(code TEXT)
RETURNS TABLE (
  id UUID,
  creator_id UUID,
  title TEXT,
  description TEXT,
  activity_emoji TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  radius INTEGER,
  start_time TIMESTAMP WITH TIME ZONE,
  end_time TIMESTAMP WITH TIME ZONE,
  max_participants INTEGER,
  participant_count INTEGER,
  is_active BOOLEAN,
  status TEXT,
  waiting_list_count INTEGER,
  share_code TEXT,
  share_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.creator_id,
    p.title,
    p.description,
    p.activity_emoji,
    ST_Y(p.location::geometry) AS latitude,
    ST_X(p.location::geometry) AS longitude,
    p.radius,
    p.start_time,
    p.end_time,
    p.max_participants,
    p.participant_count,
    p.is_active,
    p.status,
    p.waiting_list_count,
    p.share_code,
    p.share_url,
    p.created_at,
    p.updated_at
  FROM pulses p
  WHERE p.share_code = code;
END;
$$ LANGUAGE plpgsql;
