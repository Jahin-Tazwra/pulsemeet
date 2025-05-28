# 🔒 Security Setup Guide for PulseMeet

## ⚠️ IMPORTANT: Credentials Security

This repository does NOT contain sensitive API keys or credentials for security reasons. You need to set up your own credentials.

## 🔧 Required Setup Steps

### 1. Environment Variables (.env)

Create a `.env` file in the root directory with:

```env
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key
GOOGLE_MAPS_API_KEY=your_google_maps_api_key
```

### 2. Google Services Configuration

#### Android Setup:
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create/select your project
3. Add Android app with package name: `com.example.pulsemeet`
4. Download `google-services.json`
5. Place it in `android/app/google-services.json`

#### iOS Setup:
1. In the same Firebase project, add iOS app
2. Use bundle ID: `com.example.pulsemeet`
3. Download `GoogleService-Info.plist`
4. Place it in `ios/Runner/GoogleService-Info.plist`

### 3. Google Cloud Service Account (for server operations)

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Navigate to IAM & Admin > Service Accounts
3. Create a new service account
4. Download the JSON key file
5. Store it securely (NOT in this repository)
6. Reference it via environment variable or secure storage

## 🚫 What NOT to Do

- ❌ Never commit API keys to version control
- ❌ Never share credentials in public repositories
- ❌ Never hardcode secrets in source code

## ✅ Security Best Practices

- ✅ Use environment variables for secrets
- ✅ Add sensitive files to .gitignore
- ✅ Rotate API keys regularly
- ✅ Use restricted API keys with proper scopes
- ✅ Monitor for exposed secrets

## 📋 Template Files

Use the provided template files:
- `android/app/google-services.json.template`
- `ios/Runner/GoogleService-Info.plist.template`

Copy these templates and replace placeholder values with your actual credentials.
