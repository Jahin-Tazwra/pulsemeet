-- Create the pulse_media bucket if it doesn't exist
DO $$
BEGIN
    -- Check if the bucket exists
    IF NOT EXISTS (
        SELECT 1 FROM storage.buckets WHERE name = 'pulse_media'
    ) THEN
        -- Create the bucket
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
    END IF;
END $$;

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
WITH CHECK (
    bucket_id = 'pulse_media' AND
    (storage.foldername(name))[1] = 'pulse_' || (storage.foldername(name))[2]
);

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

-- Create a policy to allow pulse participants to upload media
CREATE POLICY "Pulse participants can upload media" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'pulse_media' AND
    EXISTS (
        SELECT 1 FROM pulse_participants
        WHERE pulse_participants.pulse_id = (storage.foldername(name))[2]
        AND pulse_participants.user_id = auth.uid()
        AND pulse_participants.status = 'active'
    )
);
