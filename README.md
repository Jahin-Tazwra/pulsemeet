# PulseMeet - Supabase Backend Setup

This repository contains the setup for the PulseMeet app's Supabase backend. PulseMeet is a mobile application designed to facilitate spontaneous, time-boxed meetups ("pulses") within a dynamic radius.

## Supabase Project Information

- **Project ID:** iswssbedsqvidbafaucj
- **Project URL:** https://iswssbedsqvidbafaucj.supabase.co
- **Region:** us-east-2

## Database Schema

The database schema includes the following tables:

1. **profiles** - User profiles and information
2. **pulses** - Meetup events with location data
3. **pulse_participants** - Tracks who joins which pulses
4. **chat_messages** - Ephemeral chat messages for pulses
5. **user_verifications** - Identity verification records
6. **user_settings** - User preferences and settings
7. **user_reports** - Safety reporting system
8. **user_blocks** - User blocking functionality

## Storage Buckets

The following storage buckets are configured:

1. **avatars** - For user profile pictures
2. **pulse_media** - For media shared in pulses
3. **verification_docs** - For identity verification documents

## Authentication Methods

The following authentication methods are configured:

1. **Phone verification** - Using Twilio
2. **Google OAuth** - For Google Sign-In
3. **Apple Sign-In** - For iOS compliance

## Row Level Security (RLS)

All tables have Row Level Security (RLS) policies configured to ensure data security:

- Users can only access their own private data
- Public data is accessible to all authenticated users
- Pulse participants can access pulse-specific data

## Custom Functions

The following custom PostgreSQL functions are available:

1. **find_nearby_pulses** - Find pulses near a given location
2. **expire_completed_pulses** - Automatically mark pulses as inactive when they end
3. **delete_expired_chat_messages** - Delete chat messages after they expire
4. **set_message_expiration** - Set expiration time for new chat messages

## Flutter Integration

To connect your Flutter app to this Supabase backend:

1. Use the provided `SupabaseConfig` class in `lib/config/supabase_config.dart`
2. Initialize Supabase in your app's `main.dart` file:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(MyApp());
}
```

3. Use the `SupabaseService` class in `lib/services/supabase_service.dart` to interact with the backend

## Required Dependencies

Add these dependencies to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^1.10.0
  latlong2: ^0.9.0
```

## Security Notes

- Never expose the service role key in client-side code
- Always use the anon key for client applications
- Rely on RLS policies for data security
- Keep sensitive operations in Edge Functions

## Next Steps

1. Configure actual authentication providers (Twilio, Google, Apple)
2. Set up Edge Functions for advanced functionality
3. Implement client-side code for authentication and data access
4. Test the security of RLS policies
