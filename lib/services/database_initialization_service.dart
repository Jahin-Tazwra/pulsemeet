import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service responsible for initializing and maintaining database schema
/// This handles automatic database migrations and setup during app startup
class DatabaseInitializationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Execute SQL that doesn't return results
  /// This is a helper method to handle SQL execution properly
  Future<void> _executeSql(String sql) async {
    try {
      await _supabase.rpc('execute_sql', params: {'query': sql});
    } catch (e) {
      // Handle specific error for queries that don't return tuples
      if (e is PostgrestException) {
        if (e.code == '42601' && e.message.contains('does not return tuples')) {
          // This is expected for CREATE TABLE, ALTER TABLE, etc.
          // These commands execute successfully but don't return data
          debugPrint('SQL executed successfully (no results expected)');
          return;
        } else if (e.code == 'PGRST202' &&
            e.message.contains('Could not find the function')) {
          // This could happen if the function name is wrong or not available
          debugPrint('SQL function not found: ${e.message}');
          rethrow;
        } else if (e.code == '42P07' && e.message.contains('already exists')) {
          // Table or object already exists - this is fine
          debugPrint('SQL object already exists: ${e.message}');
          return;
        } else if (e.code == '23505' && e.message.contains('duplicate key')) {
          // Duplicate key - this is fine for inserts with "IF NOT EXISTS"
          debugPrint('SQL duplicate key (ignored): ${e.message}');
          return;
        }
      }

      // Re-throw other errors
      debugPrint('SQL error: $e');
      rethrow;
    }
  }

  /// Initialize the database schema
  /// This should be called during app startup
  Future<void> initialize() async {
    try {
      debugPrint('Initializing database schema...');

      // Check and create required tables
      await _ensureTypingStatusTable();
      await _ensureConnectionsTables();
      await _ensureRatingsTable(); // Add ratings table initialization
      await _ensurePulseSharingTable(); // Add pulse sharing features
      await _ensurePulseChatKeysTable(); // Add pulse chat encryption keys
      await _ensureSecureKeyExchangeTables(); // Add secure key exchange support
      await _ensureUserDevicesTable(); // Add user devices table for FCM tokens
      await _ensurePendingNotificationsTable(); // Add pending notifications table

      // Check and configure storage buckets
      await _ensureStorageBuckets();

      debugPrint('Database initialization completed successfully');
    } catch (e) {
      debugPrint('Error initializing database: $e');
      // We don't want to crash the app if initialization fails
      // Just log the error and continue
    }
  }

  /// Ensure the typing status table exists
  Future<void> _ensureTypingStatusTable() async {
    try {
      // Check if the table exists by attempting to query it
      try {
        await _supabase.from('pulse_typing_status').select('id').limit(1);
        debugPrint('pulse_typing_status table already exists');
        return;
      } catch (e) {
        // Table doesn't exist, create it
        debugPrint('Creating pulse_typing_status table...');
      }

      // Create the table and related objects
      await _executeSql('''
        -- Create pulse_typing_status table if it doesn't exist
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
      ''');

      // Create function to update timestamp
      await _executeSql('''
        -- Create function to automatically update last_updated timestamp
        CREATE OR REPLACE FUNCTION update_typing_status_timestamp()
        RETURNS TRIGGER AS \$\$
        BEGIN
          NEW.last_updated = NOW();
          RETURN NEW;
        END;
        \$\$ LANGUAGE plpgsql;

        -- Create trigger to update timestamp on update
        DROP TRIGGER IF EXISTS update_typing_status_timestamp ON pulse_typing_status;
        CREATE TRIGGER update_typing_status_timestamp
        BEFORE UPDATE ON pulse_typing_status
        FOR EACH ROW EXECUTE FUNCTION update_typing_status_timestamp();
      ''');

      // Create cleanup function
      await _executeSql('''
        -- Create function to automatically clean up old typing statuses
        CREATE OR REPLACE FUNCTION cleanup_typing_status()
        RETURNS TRIGGER AS \$\$
        BEGIN
          -- Delete typing statuses older than 30 seconds
          DELETE FROM pulse_typing_status
          WHERE last_updated < NOW() - INTERVAL '30 seconds'
          AND is_typing = true;

          RETURN NULL;
        END;
        \$\$ LANGUAGE plpgsql;

        -- Create trigger to clean up old typing statuses
        DROP TRIGGER IF EXISTS cleanup_typing_status_trigger ON pulse_typing_status;
        CREATE TRIGGER cleanup_typing_status_trigger
        AFTER INSERT OR UPDATE ON pulse_typing_status
        FOR EACH STATEMENT EXECUTE FUNCTION cleanup_typing_status();
      ''');

      // Add RLS policies
      await _executeSql('''
        -- Add RLS policies
        ALTER TABLE pulse_typing_status ENABLE ROW LEVEL SECURITY;

        -- Policy to allow users to view typing status for pulses they're involved with
        DROP POLICY IF EXISTS "Users can view typing status for pulses they're involved with" ON pulse_typing_status;
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

        -- Policy to allow users to insert their own typing status
        DROP POLICY IF EXISTS "Users can insert their own typing status" ON pulse_typing_status;
        CREATE POLICY "Users can insert their own typing status"
        ON pulse_typing_status FOR INSERT
        TO authenticated
        WITH CHECK (user_id = auth.uid());

        -- Policy to allow users to update their own typing status
        DROP POLICY IF EXISTS "Users can update their own typing status" ON pulse_typing_status;
        CREATE POLICY "Users can update their own typing status"
        ON pulse_typing_status FOR UPDATE
        TO authenticated
        USING (user_id = auth.uid());

        -- Policy to allow users to delete their own typing status
        DROP POLICY IF EXISTS "Users can delete their own typing status" ON pulse_typing_status;
        CREATE POLICY "Users can delete their own typing status"
        ON pulse_typing_status FOR DELETE
        TO authenticated
        USING (user_id = auth.uid());
      ''');

      debugPrint(
          'Successfully created pulse_typing_status table and related objects');
    } catch (e) {
      debugPrint('Error ensuring typing status table: $e');
      // Continue with initialization even if this part fails
    }
  }

  /// Ensure storage buckets exist and are properly configured
  Future<void> _ensureStorageBuckets() async {
    try {
      // Check if the bucket exists
      final buckets = await _supabase.storage.listBuckets();
      final bucketExists =
          buckets.any((bucket) => bucket.name == 'pulse_media');

      if (!bucketExists) {
        debugPrint('Creating pulse_media bucket...');

        // Create the bucket
        await _executeSql('''
          -- Create the pulse_media bucket if it doesn't exist
          INSERT INTO storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
          VALUES ('pulse_media', 'pulse_media', false, false, 52428800, -- 50MB limit
          ARRAY[
              'image/png',
              'image/jpeg',
              'image/jpg',
              'image/gif',
              'image/webp',
              'image/svg+xml',
              'video/mp4',
              'video/quicktime',
              'video/x-msvideo',
              'video/x-ms-wmv',
              'audio/mpeg',
              'audio/mp4',
              'audio/mp3',
              'audio/ogg',
              'audio/wav',
              'audio/webm',
              'audio/aac'
          ]::text[]);
        ''');
      } else {
        debugPrint('pulse_media bucket already exists');
      }

      // Configure RLS policies for the bucket
      await _executeSql('''
        -- Drop existing policies for pulse_media bucket if they exist
        DROP POLICY IF EXISTS "Allow authenticated users to upload media" ON storage.objects;
        DROP POLICY IF EXISTS "Allow authenticated users to view media" ON storage.objects;
        DROP POLICY IF EXISTS "Allow users to update their own media" ON storage.objects;
        DROP POLICY IF EXISTS "Allow users to delete their own media" ON storage.objects;
        DROP POLICY IF EXISTS "Pulse media is publicly accessible" ON storage.objects;
        DROP POLICY IF EXISTS "Pulse participants can upload media" ON storage.objects;

        -- Create a policy to allow authenticated users to upload to pulse_media bucket
        CREATE POLICY "Allow authenticated users to upload media" ON storage.objects
        FOR INSERT TO authenticated
        WITH CHECK (bucket_id = 'pulse_media');

        -- Create a policy to allow authenticated users to select from pulse_media bucket
        CREATE POLICY "Allow authenticated users to view media" ON storage.objects
        FOR SELECT TO authenticated
        USING (bucket_id = 'pulse_media');

        -- Create a policy to allow users to update their own media
        CREATE POLICY "Allow users to update their own media" ON storage.objects
        FOR UPDATE TO authenticated
        USING (bucket_id = 'pulse_media' AND owner = auth.uid());

        -- Create a policy to allow users to delete their own media
        CREATE POLICY "Allow users to delete their own media" ON storage.objects
        FOR DELETE TO authenticated
        USING (bucket_id = 'pulse_media' AND owner = auth.uid());

        -- Create a policy to make pulse media publicly accessible
        CREATE POLICY "Pulse media is publicly accessible" ON storage.objects
        FOR SELECT TO anon
        USING (bucket_id = 'pulse_media');
      ''');

      debugPrint('Successfully configured pulse_media bucket');
    } catch (e) {
      debugPrint('Error ensuring storage buckets: $e');
      // Continue with initialization even if this part fails
    }
  }

  /// Ensure connections tables exist
  Future<void> _ensureConnectionsTables() async {
    try {
      // Check if the connections table exists by attempting to query it
      try {
        await _supabase.from('connections').select('id').limit(1);
        debugPrint('connections table already exists');
        return;
      } catch (e) {
        // Table doesn't exist, create it
        debugPrint('Creating connections tables...');
      }

      // Create the connections table
      await _executeSql('''
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
      ''');

      // Create the direct messages table
      await _executeSql('''
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
      ''');

      // Create functions and triggers
      await _executeSql('''
        -- Create function to update direct message timestamp
        CREATE OR REPLACE FUNCTION update_direct_message_timestamp()
        RETURNS TRIGGER AS \$\$
        BEGIN
          NEW.updated_at = NOW();
          RETURN NEW;
        END;
        \$\$ LANGUAGE plpgsql;

        -- Create trigger to update timestamp on update
        DROP TRIGGER IF EXISTS update_direct_message_timestamp ON direct_messages;
        CREATE TRIGGER update_direct_message_timestamp
        BEFORE UPDATE ON direct_messages
        FOR EACH ROW EXECUTE FUNCTION update_direct_message_timestamp();

        -- Create function to update connection timestamp
        CREATE OR REPLACE FUNCTION update_connection_timestamp()
        RETURNS TRIGGER AS \$\$
        BEGIN
          NEW.updated_at = NOW();
          RETURN NEW;
        END;
        \$\$ LANGUAGE plpgsql;

        -- Create trigger to update timestamp on update
        DROP TRIGGER IF EXISTS update_connection_timestamp ON connections;
        CREATE TRIGGER update_connection_timestamp
        BEFORE UPDATE ON connections
        FOR EACH ROW EXECUTE FUNCTION update_connection_timestamp();
      ''');

      // Create typing status table for direct messages
      await _executeSql('''
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
        RETURNS TRIGGER AS \$\$
        BEGIN
          NEW.last_updated = NOW();
          RETURN NEW;
        END;
        \$\$ LANGUAGE plpgsql;

        -- Create trigger to update timestamp on update
        DROP TRIGGER IF EXISTS update_dm_typing_status_timestamp ON direct_message_typing_status;
        CREATE TRIGGER update_dm_typing_status_timestamp
        BEFORE UPDATE ON direct_message_typing_status
        FOR EACH ROW EXECUTE FUNCTION update_dm_typing_status_timestamp();

        -- Create function to clean up old typing statuses
        CREATE OR REPLACE FUNCTION cleanup_dm_typing_status()
        RETURNS TRIGGER AS \$\$
        BEGIN
          -- Delete typing statuses older than 30 seconds
          DELETE FROM direct_message_typing_status
          WHERE last_updated < NOW() - INTERVAL '30 seconds'
          AND is_typing = true;

          RETURN NULL;
        END;
        \$\$ LANGUAGE plpgsql;

        -- Create trigger to clean up old typing statuses
        DROP TRIGGER IF EXISTS cleanup_dm_typing_status_trigger ON direct_message_typing_status;
        CREATE TRIGGER cleanup_dm_typing_status_trigger
        AFTER INSERT OR UPDATE ON direct_message_typing_status
        FOR EACH STATEMENT EXECUTE FUNCTION cleanup_dm_typing_status();
      ''');

      // Add RLS policies
      await _executeSql('''
        -- Add RLS policies for connections
        ALTER TABLE connections ENABLE ROW LEVEL SECURITY;

        -- Policy to allow users to view their own connections
        DROP POLICY IF EXISTS "Users can view their own connections" ON connections;
        CREATE POLICY "Users can view their own connections"
        ON connections FOR SELECT
        TO authenticated
        USING (requester_id = auth.uid() OR receiver_id = auth.uid());

        -- Policy to allow users to create connection requests
        DROP POLICY IF EXISTS "Users can create connection requests" ON connections;
        CREATE POLICY "Users can create connection requests"
        ON connections FOR INSERT
        TO authenticated
        WITH CHECK (requester_id = auth.uid());

        -- Policy to allow users to update their own connections
        DROP POLICY IF EXISTS "Users can update their own connections" ON connections;
        CREATE POLICY "Users can update their own connections"
        ON connections FOR UPDATE
        TO authenticated
        USING (requester_id = auth.uid() OR receiver_id = auth.uid());

        -- Add RLS policies for direct messages
        ALTER TABLE direct_messages ENABLE ROW LEVEL SECURITY;

        -- Policy to allow users to view their own direct messages
        DROP POLICY IF EXISTS "Users can view their own direct messages" ON direct_messages;
        CREATE POLICY "Users can view their own direct messages"
        ON direct_messages FOR SELECT
        TO authenticated
        USING (sender_id = auth.uid() OR receiver_id = auth.uid());

        -- Policy to allow users to send direct messages
        DROP POLICY IF EXISTS "Users can send direct messages" ON direct_messages;
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
        DROP POLICY IF EXISTS "Users can update their own direct messages" ON direct_messages;
        CREATE POLICY "Users can update their own direct messages"
        ON direct_messages FOR UPDATE
        TO authenticated
        USING (sender_id = auth.uid());

        -- Policy to allow users to delete their own messages
        DROP POLICY IF EXISTS "Users can delete their own direct messages" ON direct_messages;
        CREATE POLICY "Users can delete their own direct messages"
        ON direct_messages FOR DELETE
        TO authenticated
        USING (sender_id = auth.uid());

        -- Add RLS policies for direct message typing status
        ALTER TABLE direct_message_typing_status ENABLE ROW LEVEL SECURITY;

        -- Policy to allow users to view typing status for their conversations
        DROP POLICY IF EXISTS "Users can view typing status for their conversations" ON direct_message_typing_status;
        CREATE POLICY "Users can view typing status for their conversations"
        ON direct_message_typing_status FOR SELECT
        TO authenticated
        USING (user_id = auth.uid() OR receiver_id = auth.uid());

        -- Policy to allow users to insert their own typing status
        DROP POLICY IF EXISTS "Users can insert their own typing status" ON direct_message_typing_status;
        CREATE POLICY "Users can insert their own typing status"
        ON direct_message_typing_status FOR INSERT
        TO authenticated
        WITH CHECK (user_id = auth.uid());

        -- Policy to allow users to update their own typing status
        DROP POLICY IF EXISTS "Users can update their own typing status" ON direct_message_typing_status;
        CREATE POLICY "Users can update their own typing status"
        ON direct_message_typing_status FOR UPDATE
        TO authenticated
        USING (user_id = auth.uid());
      ''');

      debugPrint('Successfully created connections tables and related objects');
    } catch (e) {
      debugPrint('Error ensuring connections tables: $e');
      // Continue with initialization even if this part fails
    }
  }

  /// Ensure ratings table exists
  Future<void> _ensureRatingsTable() async {
    try {
      // Check if the ratings table exists by attempting to query it
      try {
        await _supabase.from('ratings').select('id').limit(1);
        debugPrint('ratings table already exists');
        return;
      } catch (e) {
        // Table doesn't exist, create it
        debugPrint('Creating ratings table...');
      }

      // Create the table and related objects
      await _executeSql('''
      -- Create ratings table if it doesn't exist
      CREATE TABLE IF NOT EXISTS ratings (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        rater_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
        rated_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
        pulse_id UUID NOT NULL REFERENCES pulses(id) ON DELETE CASCADE,
        rating_value INTEGER NOT NULL CHECK (rating_value BETWEEN 1 AND 5),
        comment TEXT,
        created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
        UNIQUE(rater_id, rated_user_id, pulse_id)
      );

      -- Add comment to table
      COMMENT ON TABLE ratings IS 'Stores user ratings after pulse participation';

      -- Add indexes for performance
      CREATE INDEX IF NOT EXISTS idx_ratings_rater_id ON ratings(rater_id);
      CREATE INDEX IF NOT EXISTS idx_ratings_rated_user_id ON ratings(rated_user_id);
      CREATE INDEX IF NOT EXISTS idx_ratings_pulse_id ON ratings(pulse_id);
      CREATE INDEX IF NOT EXISTS idx_ratings_rating_value ON ratings(rating_value);

      -- Add average_rating and total_ratings columns to profiles table if they don't exist
      ALTER TABLE profiles
      ADD COLUMN IF NOT EXISTS average_rating NUMERIC(3,2) DEFAULT 0,
      ADD COLUMN IF NOT EXISTS total_ratings INTEGER DEFAULT 0;
      ''');

      // Create functions and triggers
      await _executeSql('''
      -- Create function to update rating timestamp
      CREATE OR REPLACE FUNCTION update_rating_timestamp()
      RETURNS TRIGGER AS \$\$
      BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
      END;
      \$\$ LANGUAGE plpgsql;

      -- Create trigger to update timestamp on update
      DROP TRIGGER IF EXISTS update_rating_timestamp ON ratings;
      CREATE TRIGGER update_rating_timestamp
      BEFORE UPDATE ON ratings
      FOR EACH ROW EXECUTE FUNCTION update_rating_timestamp();

      -- Create function to calculate average rating for a user
      CREATE OR REPLACE FUNCTION calculate_user_rating()
      RETURNS TRIGGER AS \$\$
      DECLARE
        avg_rating NUMERIC(3,2);
        total_count INTEGER;
      BEGIN
        -- Calculate average rating and total count for the rated user
        SELECT
          COALESCE(AVG(rating_value), 0)::NUMERIC(3,2),
          COUNT(*)
        INTO
          avg_rating,
          total_count
        FROM ratings
        WHERE rated_user_id = COALESCE(NEW.rated_user_id, OLD.rated_user_id);

        -- Update the user's profile
        UPDATE profiles
        SET
          average_rating = avg_rating,
          total_ratings = total_count,
          updated_at = NOW()
        WHERE id = COALESCE(NEW.rated_user_id, OLD.rated_user_id);

        RETURN NULL;
      END;
      \$\$ LANGUAGE plpgsql;

      -- Create the trigger for insert, update, delete
      DROP TRIGGER IF EXISTS trigger_calculate_user_rating ON ratings;
      CREATE TRIGGER trigger_calculate_user_rating
      AFTER INSERT OR UPDATE OR DELETE ON ratings
      FOR EACH ROW
      EXECUTE FUNCTION calculate_user_rating();
      ''');

      // Add RLS policies
      await _executeSql('''
      -- Enable RLS on the table
      ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;

      -- Create policy to allow users to view ratings where they are the rater or rated user
      DROP POLICY IF EXISTS "Users can view ratings they're involved in" ON ratings;
      CREATE POLICY "Users can view ratings they're involved in"
      ON ratings
      FOR SELECT
      TO authenticated
      USING (rater_id = auth.uid() OR rated_user_id = auth.uid());

      -- Create policy to allow users to create ratings for pulses they participated in
      DROP POLICY IF EXISTS "Users can create ratings for pulses they participated in" ON ratings;
      CREATE POLICY "Users can create ratings for pulses they participated in"
      ON ratings
      FOR INSERT
      TO authenticated
      WITH CHECK (
        rater_id = auth.uid() AND
        rater_id != rated_user_id AND
        EXISTS (
          SELECT 1 FROM pulse_participants
          WHERE pulse_id = ratings.pulse_id
          AND user_id = auth.uid()
          AND status = 'active'
        )
      );

      -- Create policy to allow users to update their own ratings
      DROP POLICY IF EXISTS "Users can update their own ratings" ON ratings;
      CREATE POLICY "Users can update their own ratings"
      ON ratings
      FOR UPDATE
      TO authenticated
      USING (rater_id = auth.uid())
      WITH CHECK (rater_id = auth.uid());

      -- Create policy to allow users to delete their own ratings
      DROP POLICY IF EXISTS "Users can delete their own ratings" ON ratings;
      CREATE POLICY "Users can delete their own ratings"
      ON ratings
      FOR DELETE
      TO authenticated
      USING (rater_id = auth.uid());
      ''');

      debugPrint('Successfully created ratings table and related objects');
    } catch (e) {
      debugPrint('Error ensuring ratings table: $e');
      // Continue with initialization even if this part fails
    }
  }

  /// Ensure pulse sharing table exists
  Future<void> _ensurePulseSharingTable() async {
    try {
      // Check if the pulse_shares table exists by attempting to query it
      try {
        await _supabase.from('pulse_shares').select('id').limit(1);
        debugPrint('pulse_shares table already exists');
        return;
      } catch (e) {
        // Table doesn't exist, create it
        debugPrint('Creating pulse_shares table...');
      }

      // Create the table and related objects
      await _executeSql('''
      -- Create pulse_shares table if it doesn't exist
      CREATE TABLE IF NOT EXISTS pulse_shares (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        pulse_id UUID NOT NULL REFERENCES pulses(id) ON DELETE CASCADE,
        sharer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
        share_code VARCHAR(20) UNIQUE NOT NULL,
        platform VARCHAR(50),
        created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
        expires_at TIMESTAMP WITH TIME ZONE,
        click_count INTEGER DEFAULT 0,
        is_active BOOLEAN DEFAULT true
      );

      -- Add comment to table
      COMMENT ON TABLE pulse_shares IS 'Tracks pulse sharing and analytics';

      -- Add indexes for performance
      CREATE INDEX IF NOT EXISTS idx_pulse_shares_pulse_id ON pulse_shares(pulse_id);
      CREATE INDEX IF NOT EXISTS idx_pulse_shares_sharer_id ON pulse_shares(sharer_id);
      CREATE INDEX IF NOT EXISTS idx_pulse_shares_share_code ON pulse_shares(share_code);
      CREATE INDEX IF NOT EXISTS idx_pulse_shares_created_at ON pulse_shares(created_at);
      CREATE INDEX IF NOT EXISTS idx_pulse_shares_is_active ON pulse_shares(is_active);
      ''');

      // Create functions and triggers
      await _executeSql('''
      -- Create function to update pulse share timestamp
      CREATE OR REPLACE FUNCTION update_pulse_share_timestamp()
      RETURNS TRIGGER AS \$\$
      BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
      END;
      \$\$ LANGUAGE plpgsql;

      -- Create function to generate unique share codes
      CREATE OR REPLACE FUNCTION generate_share_code()
      RETURNS TEXT AS \$\$
      DECLARE
        chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
        result TEXT := '';
        i INTEGER := 0;
        code_exists BOOLEAN := true;
      BEGIN
        WHILE code_exists LOOP
          result := '';
          FOR i IN 1..8 LOOP
            result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
          END LOOP;

          SELECT EXISTS(SELECT 1 FROM pulse_shares WHERE share_code = result) INTO code_exists;
        END LOOP;

        RETURN result;
      END;
      \$\$ LANGUAGE plpgsql;

      -- Create trigger to auto-generate share codes
      CREATE OR REPLACE FUNCTION set_share_code()
      RETURNS TRIGGER AS \$\$
      BEGIN
        IF NEW.share_code IS NULL OR NEW.share_code = '' THEN
          NEW.share_code := generate_share_code();
        END IF;
        RETURN NEW;
      END;
      \$\$ LANGUAGE plpgsql;

      DROP TRIGGER IF EXISTS trigger_set_share_code ON pulse_shares;
      CREATE TRIGGER trigger_set_share_code
      BEFORE INSERT ON pulse_shares
      FOR EACH ROW
      EXECUTE FUNCTION set_share_code();
      ''');

      // Add RLS policies
      await _executeSql('''
      -- Enable RLS on the table
      ALTER TABLE pulse_shares ENABLE ROW LEVEL SECURITY;

      -- Policy to allow users to view their own shares
      DROP POLICY IF EXISTS "Users can view their own pulse shares" ON pulse_shares;
      CREATE POLICY "Users can view their own pulse shares"
      ON pulse_shares FOR SELECT
      TO authenticated
      USING (sharer_id = auth.uid());

      -- Policy to allow users to create pulse shares
      DROP POLICY IF EXISTS "Users can create pulse shares" ON pulse_shares;
      CREATE POLICY "Users can create pulse shares"
      ON pulse_shares FOR INSERT
      TO authenticated
      WITH CHECK (sharer_id = auth.uid());

      -- Policy to allow users to update their own shares
      DROP POLICY IF EXISTS "Users can update their own pulse shares" ON pulse_shares;
      CREATE POLICY "Users can update their own pulse shares"
      ON pulse_shares FOR UPDATE
      TO authenticated
      USING (sharer_id = auth.uid())
      WITH CHECK (sharer_id = auth.uid());

      -- Policy to allow users to delete their own shares
      DROP POLICY IF EXISTS "Users can delete their own pulse shares" ON pulse_shares;
      CREATE POLICY "Users can delete their own pulse shares"
      ON pulse_shares FOR DELETE
      TO authenticated
      USING (sharer_id = auth.uid());

      -- Policy to allow public access to active shares for viewing
      DROP POLICY IF EXISTS "Public can view active pulse shares" ON pulse_shares;
      CREATE POLICY "Public can view active pulse shares"
      ON pulse_shares FOR SELECT
      TO anon
      USING (is_active = true AND (expires_at IS NULL OR expires_at > NOW()));
      ''');

      debugPrint('Successfully created pulse_shares table and related objects');
    } catch (e) {
      debugPrint('Error ensuring pulse_shares table: $e');
      // Continue with initialization even if this part fails
    }
  }

  /// Ensure pulse chat keys table exists for end-to-end encryption
  Future<void> _ensurePulseChatKeysTable() async {
    try {
      // Check if the pulse_chat_keys table exists by attempting to query it
      try {
        await _supabase.from('pulse_chat_keys').select('id').limit(1);
        debugPrint('pulse_chat_keys table already exists');
        return;
      } catch (e) {
        // Table doesn't exist, create it
        debugPrint('Creating pulse_chat_keys table...');
      }

      // Create the table and related objects
      await _executeSql('''
      -- Create pulse_chat_keys table if it doesn't exist
      CREATE TABLE IF NOT EXISTS pulse_chat_keys (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        pulse_id UUID NOT NULL REFERENCES pulses(id) ON DELETE CASCADE,
        key_id VARCHAR(255) NOT NULL UNIQUE,
        symmetric_key TEXT NOT NULL,
        created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
        created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
        expires_at TIMESTAMP WITH TIME ZONE,
        version INTEGER DEFAULT 1,
        is_active BOOLEAN DEFAULT true,
        UNIQUE(pulse_id, version)
      );

      -- Add comment to table
      COMMENT ON TABLE pulse_chat_keys IS 'Stores shared encryption keys for pulse chats';

      -- Add indexes for performance
      CREATE INDEX IF NOT EXISTS idx_pulse_chat_keys_pulse_id ON pulse_chat_keys(pulse_id);
      CREATE INDEX IF NOT EXISTS idx_pulse_chat_keys_key_id ON pulse_chat_keys(key_id);
      CREATE INDEX IF NOT EXISTS idx_pulse_chat_keys_created_by ON pulse_chat_keys(created_by);
      CREATE INDEX IF NOT EXISTS idx_pulse_chat_keys_is_active ON pulse_chat_keys(is_active);
      ''');

      // Add RLS policies
      await _executeSql('''
      -- Enable RLS on the table
      ALTER TABLE pulse_chat_keys ENABLE ROW LEVEL SECURITY;

      -- Policy to allow pulse participants to view chat keys
      DROP POLICY IF EXISTS "Pulse participants can view chat keys" ON pulse_chat_keys;
      CREATE POLICY "Pulse participants can view chat keys"
      ON pulse_chat_keys FOR SELECT
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM pulse_participants
          WHERE pulse_participants.pulse_id = pulse_chat_keys.pulse_id
          AND pulse_participants.user_id = auth.uid()
          AND pulse_participants.status = 'active'
        ) OR
        EXISTS (
          SELECT 1 FROM pulses
          WHERE pulses.id = pulse_chat_keys.pulse_id
          AND pulses.creator_id = auth.uid()
        )
      );

      -- Policy to allow pulse creators to create chat keys
      DROP POLICY IF EXISTS "Pulse creators can create chat keys" ON pulse_chat_keys;
      CREATE POLICY "Pulse creators can create chat keys"
      ON pulse_chat_keys FOR INSERT
      TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM pulses
          WHERE pulses.id = pulse_id
          AND pulses.creator_id = auth.uid()
        ) OR
        EXISTS (
          SELECT 1 FROM pulse_participants
          WHERE pulse_participants.pulse_id = pulse_chat_keys.pulse_id
          AND pulse_participants.user_id = auth.uid()
          AND pulse_participants.status = 'active'
        )
      );

      -- Policy to allow key creators to update their keys
      DROP POLICY IF EXISTS "Key creators can update chat keys" ON pulse_chat_keys;
      CREATE POLICY "Key creators can update chat keys"
      ON pulse_chat_keys FOR UPDATE
      TO authenticated
      USING (created_by = auth.uid())
      WITH CHECK (created_by = auth.uid());
      ''');

      debugPrint(
          'Successfully created pulse_chat_keys table and related objects');
    } catch (e) {
      debugPrint('Error ensuring pulse_chat_keys table: $e');
      // Continue with initialization even if this part fails
    }
  }

  /// Ensure secure key exchange tables exist for true E2E encryption
  Future<void> _ensureSecureKeyExchangeTables() async {
    try {
      debugPrint('Ensuring secure key exchange tables...');

      // Create key exchange status table
      await _executeSql('''
      -- Create key exchange status table if it doesn't exist
      CREATE TABLE IF NOT EXISTS key_exchange_status (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user1_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
        user2_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
        conversation_id VARCHAR(255) NOT NULL,
        conversation_type VARCHAR(20) NOT NULL CHECK (conversation_type IN ('direct', 'pulse')),
        key_exchange_completed BOOLEAN DEFAULT false,
        last_key_rotation TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

        -- Ensure unique key exchange per user pair per conversation
        UNIQUE(user1_id, user2_id, conversation_id),

        -- Ensure user1_id < user2_id for consistent ordering
        CHECK (user1_id < user2_id)
      );

      -- Add indexes for performance
      CREATE INDEX IF NOT EXISTS idx_key_exchange_status_users ON key_exchange_status(user1_id, user2_id);
      CREATE INDEX IF NOT EXISTS idx_key_exchange_status_conversation ON key_exchange_status(conversation_id);
      CREATE INDEX IF NOT EXISTS idx_key_exchange_status_completed ON key_exchange_status(key_exchange_completed);
      ''');

      // Create migration status table
      await _executeSql('''
      -- Create migration status table if it doesn't exist
      CREATE TABLE IF NOT EXISTS e2e_migration_status (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        migration_name VARCHAR(100) NOT NULL UNIQUE,
        started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        completed_at TIMESTAMP WITH TIME ZONE,
        status VARCHAR(20) DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'failed')),
        error_message TEXT,
        affected_records INTEGER DEFAULT 0
      );
      ''');

      // Add RLS policies
      await _executeSql('''
      -- Enable RLS on key exchange status table
      ALTER TABLE key_exchange_status ENABLE ROW LEVEL SECURITY;

      -- Policy to allow users to view their own key exchange status
      DROP POLICY IF EXISTS "Users can view their own key exchange status" ON key_exchange_status;
      CREATE POLICY "Users can view their own key exchange status" ON key_exchange_status
      FOR SELECT TO authenticated
      USING (auth.uid() = user1_id OR auth.uid() = user2_id);

      -- Policy to allow users to create key exchange records
      DROP POLICY IF EXISTS "Users can create key exchange records" ON key_exchange_status;
      CREATE POLICY "Users can create key exchange records" ON key_exchange_status
      FOR INSERT TO authenticated
      WITH CHECK (auth.uid() = user1_id OR auth.uid() = user2_id);

      -- Policy to allow users to update their key exchange status
      DROP POLICY IF EXISTS "Users can update their key exchange status" ON key_exchange_status;
      CREATE POLICY "Users can update their key exchange status" ON key_exchange_status
      FOR UPDATE TO authenticated
      USING (auth.uid() = user1_id OR auth.uid() = user2_id)
      WITH CHECK (auth.uid() = user1_id OR auth.uid() = user2_id);

      -- Enable RLS on migration status table (admin only)
      ALTER TABLE e2e_migration_status ENABLE ROW LEVEL SECURITY;

      -- Only allow authenticated users to read migration status
      DROP POLICY IF EXISTS "Users can view migration status" ON e2e_migration_status;
      CREATE POLICY "Users can view migration status" ON e2e_migration_status
      FOR SELECT TO authenticated
      USING (true);
      ''');

      // Update pulse_chat_keys table for secure key exchange
      await _executeSql('''
      -- Add secure key exchange columns to pulse_chat_keys if they don't exist
      ALTER TABLE pulse_chat_keys
      ADD COLUMN IF NOT EXISTS key_exchange_method VARCHAR(50) DEFAULT 'ECDH-HKDF-SHA256',
      ADD COLUMN IF NOT EXISTS requires_key_derivation BOOLEAN DEFAULT true,
      ADD COLUMN IF NOT EXISTS migration_completed BOOLEAN DEFAULT false;

      -- Remove symmetric_key column if it still exists (migration safety)
      ALTER TABLE pulse_chat_keys DROP COLUMN IF EXISTS symmetric_key;

      -- Update existing records to use secure key derivation
      UPDATE pulse_chat_keys
      SET
        requires_key_derivation = true,
        migration_completed = true,
        key_exchange_method = 'ECDH-HKDF-SHA256'
      WHERE requires_key_derivation IS NULL;

      -- Add comments explaining the security model
      COMMENT ON TABLE pulse_chat_keys IS 'Pulse chat key metadata - symmetric keys derived locally using ECDH, never stored on server';
      COMMENT ON COLUMN pulse_chat_keys.key_exchange_method IS 'Method used for key derivation (ECDH-HKDF-SHA256)';
      COMMENT ON COLUMN pulse_chat_keys.requires_key_derivation IS 'True if keys must be derived locally';
      COMMENT ON COLUMN pulse_chat_keys.migration_completed IS 'True if migrated to secure key exchange';
      ''');

      debugPrint('Successfully created secure key exchange tables');
    } catch (e) {
      debugPrint('Error ensuring secure key exchange tables: $e');
      // Continue with initialization even if this part fails
    }
  }

  /// Ensure user devices table exists for FCM tokens
  Future<void> _ensureUserDevicesTable() async {
    try {
      // Check if the table exists by attempting to query it
      try {
        await _supabase.from('user_devices').select('id').limit(1);
        debugPrint('user_devices table already exists');
        return;
      } catch (e) {
        // Table doesn't exist, create it
        debugPrint('Creating user_devices table...');
      }

      // Create the user_devices table
      await _executeSql('''
        -- Create user_devices table for FCM tokens
        CREATE TABLE IF NOT EXISTS user_devices (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
          device_token TEXT NOT NULL,
          device_type VARCHAR(20) NOT NULL CHECK (device_type IN ('ios', 'android', 'web')),
          device_name VARCHAR(255),
          app_version VARCHAR(50),
          os_version VARCHAR(50),
          is_active BOOLEAN NOT NULL DEFAULT true,
          last_seen TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
          created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
          UNIQUE(user_id, device_token)
        );

        -- Add comment to table
        COMMENT ON TABLE user_devices IS 'Stores user device information and FCM tokens for push notifications';

        -- Add indexes for performance
        CREATE INDEX IF NOT EXISTS idx_user_devices_user_id ON user_devices(user_id);
        CREATE INDEX IF NOT EXISTS idx_user_devices_device_token ON user_devices(device_token);
        CREATE INDEX IF NOT EXISTS idx_user_devices_is_active ON user_devices(is_active);
        CREATE INDEX IF NOT EXISTS idx_user_devices_last_seen ON user_devices(last_seen);
      ''');

      // Create functions and triggers
      await _executeSql('''
        -- Create function to update user device timestamp
        CREATE OR REPLACE FUNCTION update_user_device_timestamp()
        RETURNS TRIGGER AS \$\$
        BEGIN
          NEW.updated_at = NOW();
          NEW.last_seen = NOW();
          RETURN NEW;
        END;
        \$\$ LANGUAGE plpgsql;

        -- Create trigger to update timestamp on update
        DROP TRIGGER IF EXISTS update_user_device_timestamp ON user_devices;
        CREATE TRIGGER update_user_device_timestamp
        BEFORE UPDATE ON user_devices
        FOR EACH ROW EXECUTE FUNCTION update_user_device_timestamp();

        -- Create function to clean up old inactive devices
        CREATE OR REPLACE FUNCTION cleanup_inactive_devices()
        RETURNS TRIGGER AS \$\$
        BEGIN
          -- Mark devices as inactive if not seen for 30 days
          UPDATE user_devices
          SET is_active = false
          WHERE last_seen < NOW() - INTERVAL '30 days'
          AND is_active = true;

          -- Delete very old inactive devices (90 days)
          DELETE FROM user_devices
          WHERE last_seen < NOW() - INTERVAL '90 days'
          AND is_active = false;

          RETURN NULL;
        END;
        \$\$ LANGUAGE plpgsql;

        -- Create trigger to clean up old devices
        DROP TRIGGER IF EXISTS cleanup_inactive_devices_trigger ON user_devices;
        CREATE TRIGGER cleanup_inactive_devices_trigger
        AFTER INSERT OR UPDATE ON user_devices
        FOR EACH STATEMENT EXECUTE FUNCTION cleanup_inactive_devices();
      ''');

      // Add RLS policies
      await _executeSql('''
        -- Add RLS policies for user_devices
        ALTER TABLE user_devices ENABLE ROW LEVEL SECURITY;

        -- Policy to allow users to view their own devices
        DROP POLICY IF EXISTS "Users can view their own devices" ON user_devices;
        CREATE POLICY "Users can view their own devices"
        ON user_devices FOR SELECT
        TO authenticated
        USING (user_id = auth.uid());

        -- Policy to allow users to insert their own devices
        DROP POLICY IF EXISTS "Users can insert their own devices" ON user_devices;
        CREATE POLICY "Users can insert their own devices"
        ON user_devices FOR INSERT
        TO authenticated
        WITH CHECK (user_id = auth.uid());

        -- Policy to allow users to update their own devices
        DROP POLICY IF EXISTS "Users can update their own devices" ON user_devices;
        CREATE POLICY "Users can update their own devices"
        ON user_devices FOR UPDATE
        TO authenticated
        USING (user_id = auth.uid());

        -- Policy to allow users to delete their own devices
        DROP POLICY IF EXISTS "Users can delete their own devices" ON user_devices;
        CREATE POLICY "Users can delete their own devices"
        ON user_devices FOR DELETE
        TO authenticated
        USING (user_id = auth.uid());
      ''');

      debugPrint('Successfully created user_devices table and related objects');
    } catch (e) {
      debugPrint('Error ensuring user devices table: $e');
      // Continue with initialization even if this part fails
    }
  }

  /// Ensure pending notifications table exists for real-time notification delivery
  Future<void> _ensurePendingNotificationsTable() async {
    try {
      // Check if the table exists by attempting to query it
      try {
        await _supabase.from('pending_notifications').select('id').limit(1);
        debugPrint('pending_notifications table already exists');
        return;
      } catch (e) {
        // Table doesn't exist, create it
        debugPrint('Creating pending_notifications table...');
      }

      // Create the pending_notifications table
      await _executeSql('''
        -- Create pending_notifications table for real-time notification delivery
        CREATE TABLE IF NOT EXISTS pending_notifications (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
          device_token TEXT NOT NULL,
          title TEXT NOT NULL,
          body TEXT NOT NULL,
          data JSONB DEFAULT '{}',
          device_type VARCHAR(20) DEFAULT 'unknown',
          status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'delivered', 'failed')),
          created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
          delivered_at TIMESTAMP WITH TIME ZONE,
          error_message TEXT
        );

        -- Add comment to table
        COMMENT ON TABLE pending_notifications IS 'Stores pending push notifications for real-time delivery';

        -- Add indexes for performance
        CREATE INDEX IF NOT EXISTS idx_pending_notifications_user_id ON pending_notifications(user_id);
        CREATE INDEX IF NOT EXISTS idx_pending_notifications_device_token ON pending_notifications(device_token);
        CREATE INDEX IF NOT EXISTS idx_pending_notifications_status ON pending_notifications(status);
        CREATE INDEX IF NOT EXISTS idx_pending_notifications_created_at ON pending_notifications(created_at);
      ''');

      // Create functions and triggers
      await _executeSql('''
        -- Create function to clean up old notifications
        CREATE OR REPLACE FUNCTION cleanup_old_notifications()
        RETURNS TRIGGER AS \$\$
        BEGIN
          -- Delete notifications older than 7 days
          DELETE FROM pending_notifications
          WHERE created_at < NOW() - INTERVAL '7 days';

          RETURN NULL;
        END;
        \$\$ LANGUAGE plpgsql;

        -- Create trigger to clean up old notifications
        DROP TRIGGER IF EXISTS cleanup_old_notifications_trigger ON pending_notifications;
        CREATE TRIGGER cleanup_old_notifications_trigger
        AFTER INSERT ON pending_notifications
        FOR EACH STATEMENT EXECUTE FUNCTION cleanup_old_notifications();
      ''');

      // Add RLS policies
      await _executeSql('''
        -- Add RLS policies for pending_notifications
        ALTER TABLE pending_notifications ENABLE ROW LEVEL SECURITY;

        -- Policy to allow users to view their own notifications
        DROP POLICY IF EXISTS "Users can view their own notifications" ON pending_notifications;
        CREATE POLICY "Users can view their own notifications"
        ON pending_notifications FOR SELECT
        TO authenticated
        USING (user_id = auth.uid());

        -- Policy to allow service role to insert notifications
        DROP POLICY IF EXISTS "Service role can insert notifications" ON pending_notifications;
        CREATE POLICY "Service role can insert notifications"
        ON pending_notifications FOR INSERT
        TO service_role
        WITH CHECK (true);

        -- Policy to allow users to update their own notifications
        DROP POLICY IF EXISTS "Users can update their own notifications" ON pending_notifications;
        CREATE POLICY "Users can update their own notifications"
        ON pending_notifications FOR UPDATE
        TO authenticated
        USING (user_id = auth.uid());

        -- Policy to allow users to delete their own notifications
        DROP POLICY IF EXISTS "Users can delete their own notifications" ON pending_notifications;
        CREATE POLICY "Users can delete their own notifications"
        ON pending_notifications FOR DELETE
        TO authenticated
        USING (user_id = auth.uid());
      ''');

      debugPrint(
          'Successfully created pending_notifications table and related objects');
    } catch (e) {
      debugPrint('Error ensuring pending notifications table: $e');
      // Continue with initialization even if this part fails
    }
  }
}
