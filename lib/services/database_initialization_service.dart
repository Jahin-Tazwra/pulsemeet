import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service responsible for initializing and maintaining database schema
/// This handles automatic database migrations and setup during app startup
class DatabaseInitializationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Initialize the database schema
  /// This should be called during app startup
  Future<void> initialize() async {
    try {
      debugPrint('Initializing database schema...');

      // Check and create required tables
      await _ensureTypingStatusTable();
      await _ensureConnectionsTables();
      await _ensureRatingsTable(); // Add ratings table initialization

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
      await _supabase.rpc('exec_sql', params: {
        'query': '''
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
        '''
      });

      // Create function to update timestamp
      await _supabase.rpc('exec_sql', params: {
        'query': '''
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
        '''
      });

      // Create cleanup function
      await _supabase.rpc('exec_sql', params: {
        'query': '''
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
        '''
      });

      // Add RLS policies
      await _supabase.rpc('exec_sql', params: {
        'query': '''
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
        '''
      });

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
        await _supabase.rpc('exec_sql', params: {
          'query': '''
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
          '''
        });
      } else {
        debugPrint('pulse_media bucket already exists');
      }

      // Configure RLS policies for the bucket
      await _supabase.rpc('exec_sql', params: {
        'query': '''
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
        '''
      });

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
      await _supabase.rpc('exec_sql', params: {
        'query': '''
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
        '''
      });

      // Create the direct messages table
      await _supabase.rpc('exec_sql', params: {
        'query': '''
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
        '''
      });

      // Create functions and triggers
      await _supabase.rpc('exec_sql', params: {
        'query': '''
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
        '''
      });

      // Create typing status table for direct messages
      await _supabase.rpc('exec_sql', params: {
        'query': '''
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
        '''
      });

      // Add RLS policies
      await _supabase.rpc('exec_sql', params: {
        'query': '''
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
        '''
      });

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
      await _supabase.rpc('exec_sql', params: {
        'query': '''
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
      '''
      });

      // Create functions and triggers
      await _supabase.rpc('exec_sql', params: {
        'query': '''
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
      '''
      });

      // Add RLS policies
      await _supabase.rpc('exec_sql', params: {
        'query': '''
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
      '''
      });

      debugPrint('Successfully created ratings table and related objects');
    } catch (e) {
      debugPrint('Error ensuring ratings table: $e');
      // Continue with initialization even if this part fails
    }
  }
}
