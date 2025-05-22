-- Create pulse_share_events table
CREATE TABLE IF NOT EXISTS pulse_share_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  pulse_id UUID REFERENCES pulses(id) ON DELETE CASCADE,
  share_code TEXT NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('share', 'view', 'install')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_pulse_share_events_pulse_id ON pulse_share_events(pulse_id);
CREATE INDEX IF NOT EXISTS idx_pulse_share_events_share_code ON pulse_share_events(share_code);
CREATE INDEX IF NOT EXISTS idx_pulse_share_events_event_type ON pulse_share_events(event_type);

-- Create function to get pulse share analytics
CREATE OR REPLACE FUNCTION get_pulse_share_analytics(pulse_id_param UUID)
RETURNS JSON AS $$
DECLARE
  share_count INTEGER;
  view_count INTEGER;
  install_count INTEGER;
  result JSON;
BEGIN
  -- Count shares
  SELECT COUNT(*) INTO share_count
  FROM pulse_share_events
  WHERE pulse_id = pulse_id_param AND event_type = 'share';
  
  -- Count views
  SELECT COUNT(*) INTO view_count
  FROM pulse_share_events
  WHERE pulse_id = pulse_id_param AND event_type = 'view';
  
  -- Count installs
  SELECT COUNT(*) INTO install_count
  FROM pulse_share_events
  WHERE pulse_id = pulse_id_param AND event_type = 'install';
  
  -- Create result JSON
  result := json_build_object(
    'shares', share_count,
    'views', view_count,
    'installs', install_count
  );
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;
