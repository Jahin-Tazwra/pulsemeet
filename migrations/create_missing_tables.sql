-- Create missing database tables for PulseMeet
-- This migration creates the critical missing tables identified in the audit

-- 1. Create pulse_waiting_list table
CREATE TABLE IF NOT EXISTS pulse_waiting_list (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pulse_id UUID NOT NULL REFERENCES pulses(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting', 'promoted', 'left')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    promoted_at TIMESTAMP WITH TIME ZONE,
    left_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Ensure unique user per pulse in waiting list
    UNIQUE(pulse_id, user_id)
);

-- Create index for efficient queries
CREATE INDEX IF NOT EXISTS idx_pulse_waiting_list_pulse_id ON pulse_waiting_list(pulse_id);
CREATE INDEX IF NOT EXISTS idx_pulse_waiting_list_user_id ON pulse_waiting_list(user_id);
CREATE INDEX IF NOT EXISTS idx_pulse_waiting_list_status ON pulse_waiting_list(status);
CREATE INDEX IF NOT EXISTS idx_pulse_waiting_list_position ON pulse_waiting_list(pulse_id, position);

-- Enable RLS
ALTER TABLE pulse_waiting_list ENABLE ROW LEVEL SECURITY;

-- RLS Policies for pulse_waiting_list
CREATE POLICY "Users can view waiting list for pulses they can see" ON pulse_waiting_list
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM pulses
            WHERE pulses.id = pulse_waiting_list.pulse_id
        )
    );

CREATE POLICY "Users can join waiting lists" ON pulse_waiting_list
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own waiting list entries" ON pulse_waiting_list
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own waiting list entries" ON pulse_waiting_list
    FOR DELETE USING (auth.uid() = user_id);

-- 2. Create favorite_hosts table
CREATE TABLE IF NOT EXISTS favorite_hosts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    host_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Ensure unique favorite per user-host pair
    UNIQUE(user_id, host_id),

    -- Prevent users from favoriting themselves
    CHECK (user_id != host_id)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_favorite_hosts_user_id ON favorite_hosts(user_id);
CREATE INDEX IF NOT EXISTS idx_favorite_hosts_host_id ON favorite_hosts(host_id);

-- Enable RLS
ALTER TABLE favorite_hosts ENABLE ROW LEVEL SECURITY;

-- RLS Policies for favorite_hosts
CREATE POLICY "Users can view their own favorite hosts" ON favorite_hosts
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can add favorite hosts" ON favorite_hosts
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove their favorite hosts" ON favorite_hosts
    FOR DELETE USING (auth.uid() = user_id);

-- 3. Create mentions table
CREATE TABLE IF NOT EXISTS mentions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL, -- Can reference chat_messages or direct_messages
    message_type TEXT NOT NULL DEFAULT 'chat' CHECK (message_type IN ('chat', 'direct')),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    mentioned_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Ensure unique mention per message-user pair
    UNIQUE(message_id, user_id, message_type)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_mentions_user_id ON mentions(user_id);
CREATE INDEX IF NOT EXISTS idx_mentions_message_id ON mentions(message_id);
CREATE INDEX IF NOT EXISTS idx_mentions_is_read ON mentions(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_mentions_created_at ON mentions(created_at);

-- Enable RLS
ALTER TABLE mentions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for mentions
CREATE POLICY "Users can view their own mentions" ON mentions
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create mentions" ON mentions
    FOR INSERT WITH CHECK (auth.uid() = mentioned_by);

CREATE POLICY "Users can update their own mentions" ON mentions
    FOR UPDATE USING (auth.uid() = user_id);

-- 4. Create pulse_share_events table for analytics
CREATE TABLE IF NOT EXISTS pulse_share_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pulse_id UUID REFERENCES pulses(id) ON DELETE CASCADE,
    share_code TEXT NOT NULL,
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL, -- Can be null for anonymous events
    event_type TEXT NOT NULL CHECK (event_type IN ('share', 'view', 'install')),
    ip_address INET,
    user_agent TEXT,
    referrer TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_pulse_share_events_pulse_id ON pulse_share_events(pulse_id);
CREATE INDEX IF NOT EXISTS idx_pulse_share_events_share_code ON pulse_share_events(share_code);
CREATE INDEX IF NOT EXISTS idx_pulse_share_events_event_type ON pulse_share_events(event_type);
CREATE INDEX IF NOT EXISTS idx_pulse_share_events_created_at ON pulse_share_events(created_at);

-- Enable RLS
ALTER TABLE pulse_share_events ENABLE ROW LEVEL SECURITY;

-- RLS Policies for pulse_share_events
CREATE POLICY "Users can view analytics for their own pulses" ON pulse_share_events
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM pulses
            WHERE pulses.id = pulse_share_events.pulse_id
            AND pulses.creator_id = auth.uid()
        )
    );

CREATE POLICY "Anyone can create share events" ON pulse_share_events
    FOR INSERT WITH CHECK (true); -- Allow anonymous tracking

-- Add update timestamp triggers
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply triggers to tables with updated_at columns
CREATE TRIGGER update_pulse_waiting_list_updated_at
    BEFORE UPDATE ON pulse_waiting_list
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_favorite_hosts_updated_at
    BEFORE UPDATE ON favorite_hosts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_mentions_updated_at
    BEFORE UPDATE ON mentions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
