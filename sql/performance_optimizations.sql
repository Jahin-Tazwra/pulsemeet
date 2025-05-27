-- Performance optimization SQL functions for PulseMeet chat system
-- These functions support the DatabaseOptimizationService

-- Function to execute arbitrary SQL (for index creation)
CREATE OR REPLACE FUNCTION execute_sql(sql text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  EXECUTE sql;
END;
$$;

-- Function to batch load conversation messages efficiently
CREATE OR REPLACE FUNCTION batch_load_conversation_messages(
  conversation_ids text[],
  limit_per_conversation integer DEFAULT 20
)
RETURNS TABLE (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  message_type text,
  content text,
  created_at timestamptz,
  updated_at timestamptz,
  status text,
  is_encrypted boolean,
  encryption_metadata jsonb,
  key_version integer,
  media_data jsonb,
  reply_to_id uuid,
  is_deleted boolean,
  is_edited boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT ON (m.conversation_id, m.created_at)
    m.id,
    m.conversation_id,
    m.sender_id,
    m.message_type,
    m.content,
    m.created_at,
    m.updated_at,
    m.status,
    m.is_encrypted,
    m.encryption_metadata,
    m.key_version,
    m.media_data,
    m.reply_to_id,
    m.is_deleted,
    m.is_edited
  FROM messages m
  WHERE m.conversation_id = ANY(conversation_ids)
    AND m.is_deleted = false
  ORDER BY m.conversation_id, m.created_at DESC
  LIMIT limit_per_conversation;
END;
$$;

-- Function to get unread message counts efficiently
CREATE OR REPLACE FUNCTION get_unread_counts(conversation_ids text[])
RETURNS TABLE (
  conversation_id uuid,
  unread_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    m.conversation_id,
    COUNT(*) as unread_count
  FROM messages m
  JOIN conversation_participants cp ON cp.conversation_id = m.conversation_id
  WHERE m.conversation_id = ANY(conversation_ids)
    AND m.created_at > COALESCE(cp.last_read_at, '1970-01-01'::timestamptz)
    AND m.sender_id != cp.user_id
    AND m.is_deleted = false
    AND cp.user_id = auth.uid()
  GROUP BY m.conversation_id;
END;
$$;

-- Function to optimize RLS policies (placeholder)
CREATE OR REPLACE FUNCTION optimize_rls_policies()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- This would contain RLS policy optimizations
  -- For now, just a placeholder that does nothing
  NULL;
END;
$$;

-- Function to analyze conversation query patterns
CREATE OR REPLACE FUNCTION analyze_conversation_queries(conversation_id_param uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- This would analyze query patterns and suggest optimizations
  -- For now, just a placeholder
  NULL;
END;
$$;

-- Create optimal indexes for message queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_conversation_time 
ON messages (conversation_id, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_status 
ON messages (conversation_id, status, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_sender 
ON messages (sender_id, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_unread 
ON messages (conversation_id, status, sender_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversation_participants_user 
ON conversation_participants (user_id, last_read_at DESC);

-- Index for encrypted message queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_encryption 
ON messages (conversation_id, is_encrypted, key_version);

-- Index for message types
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_type 
ON messages (conversation_id, message_type, created_at DESC);

-- Composite index for real-time subscriptions
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_realtime 
ON messages (conversation_id, created_at, id) 
WHERE is_deleted = false;

-- Function to get conversation message statistics
CREATE OR REPLACE FUNCTION get_conversation_stats(conversation_id_param uuid)
RETURNS TABLE (
  total_messages bigint,
  encrypted_messages bigint,
  media_messages bigint,
  last_message_at timestamptz,
  participants_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(*) as total_messages,
    COUNT(*) FILTER (WHERE is_encrypted = true) as encrypted_messages,
    COUNT(*) FILTER (WHERE message_type IN ('image', 'video', 'audio', 'file')) as media_messages,
    MAX(created_at) as last_message_at,
    (SELECT COUNT(*) FROM conversation_participants WHERE conversation_id = conversation_id_param) as participants_count
  FROM messages 
  WHERE conversation_id = conversation_id_param 
    AND is_deleted = false;
END;
$$;

-- Function to clean up old message cache data
CREATE OR REPLACE FUNCTION cleanup_old_messages(days_old integer DEFAULT 90)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count integer;
BEGIN
  -- This would clean up old messages based on retention policy
  -- For now, just return 0
  deleted_count := 0;
  RETURN deleted_count;
END;
$$;

-- Function to optimize message queries for a specific user
CREATE OR REPLACE FUNCTION optimize_user_message_queries(user_id_param uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- This would optimize queries for a specific user's message patterns
  -- Could include creating user-specific partial indexes
  NULL;
END;
$$;

-- Performance monitoring view
CREATE OR REPLACE VIEW message_performance_stats AS
SELECT 
  conversation_id,
  COUNT(*) as message_count,
  COUNT(*) FILTER (WHERE is_encrypted = true) as encrypted_count,
  COUNT(*) FILTER (WHERE message_type != 'text') as media_count,
  AVG(EXTRACT(EPOCH FROM (updated_at - created_at))) as avg_processing_time,
  MAX(created_at) as last_activity
FROM messages 
WHERE created_at > NOW() - INTERVAL '7 days'
  AND is_deleted = false
GROUP BY conversation_id
ORDER BY message_count DESC;

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION execute_sql(text) TO authenticated;
GRANT EXECUTE ON FUNCTION batch_load_conversation_messages(text[], integer) TO authenticated;
GRANT EXECUTE ON FUNCTION get_unread_counts(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION optimize_rls_policies() TO authenticated;
GRANT EXECUTE ON FUNCTION analyze_conversation_queries(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_conversation_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_old_messages(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION optimize_user_message_queries(uuid) TO authenticated;
GRANT SELECT ON message_performance_stats TO authenticated;
