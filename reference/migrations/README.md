# Database Migration Reference

This folder contains SQL migration scripts for reference purposes. These migrations are now handled automatically by the `DatabaseInitializationService` during app startup.

## Files

- `typing_status.sql`: Creates the `pulse_typing_status` table and related objects
- `fix_storage_bucket.sql`: Configures the `pulse_media` storage bucket

## Implementation

The actual implementation of these migrations is in `lib/services/database_initialization_service.dart`. The service:

1. Checks if required database objects exist
2. Creates them if they don't exist
3. Configures proper permissions and policies

This approach ensures that the database schema is always up-to-date without requiring user intervention.

## Manual Execution

If you need to manually execute these migrations:

1. Go to your Supabase project dashboard
2. Navigate to the SQL Editor
3. Copy and paste the SQL from the appropriate file
4. Run the SQL script

Note: Manual execution should only be necessary for development or troubleshooting purposes.
