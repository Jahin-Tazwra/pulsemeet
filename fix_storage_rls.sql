-- Drop existing policies for pulse_media bucket if they exist
DROP POLICY IF EXISTS "Allow authenticated users to upload media" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated users to view media" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to update their own media" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to delete their own media" ON storage.objects;

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
