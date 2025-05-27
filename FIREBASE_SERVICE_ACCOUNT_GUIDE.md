# 🔑 Firebase Service Account Setup Guide

Since you don't see the legacy "Server Key" in Firebase Console (which is deprecated), follow this guide to get the modern service account credentials.

## 📋 Step-by-Step Instructions

### 1. Access Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project (or create one if you haven't)

### 2. Navigate to Service Accounts
1. Click the **⚙️ Settings** (gear icon) in the left sidebar
2. Select **Project settings**
3. Click on the **Service accounts** tab

### 3. Generate Service Account Key
1. You should see a section called **"Firebase Admin SDK"**
2. Make sure **Node.js** is selected in the dropdown
3. Click **"Generate new private key"** button
4. A dialog will appear warning about keeping the key secure
5. Click **"Generate key"**
6. A JSON file will be downloaded to your computer

### 4. Understand the Service Account File
The downloaded JSON file contains:
```json
{
  "type": "service_account",
  "project_id": "your-project-id-here",
  "private_key_id": "some-key-id",
  "private_key": "-----BEGIN PRIVATE KEY-----\nYour private key here\n-----END PRIVATE KEY-----\n",
  "client_email": "firebase-adminsdk-xxxxx@your-project-id.iam.gserviceaccount.com",
  "client_id": "123456789012345678901",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-xxxxx%40your-project-id.iam.gserviceaccount.com"
}
```

### 5. Add to Supabase Environment Variables
1. Go to your [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your project
3. Go to **Settings** → **Environment Variables**
4. Click **"Add new variable"**
5. Set:
   - **Name**: `FIREBASE_SERVICE_ACCOUNT`
   - **Value**: Copy the **entire contents** of the JSON file as a single string

**⚠️ Important**: Copy the entire JSON content, including all the curly braces, quotes, and newlines.

### 6. Alternative: Using Supabase CLI
If you prefer using the CLI:

```bash
# Set the environment variable
supabase secrets set FIREBASE_SERVICE_ACCOUNT='{"type":"service_account","project_id":"your-project-id",...}'
```

## 🔒 Security Best Practices

### ✅ DO:
- Keep the service account file secure
- Never commit it to version control
- Use environment variables for the credentials
- Rotate keys periodically
- Limit service account permissions

### ❌ DON'T:
- Share the service account file
- Store it in your codebase
- Use it in client-side code
- Leave it in downloads folder

## 🧪 Testing the Setup

After setting up the service account, you can test it:

1. **Deploy the Edge Function**:
```bash
supabase functions deploy send-push-notification
```

2. **Test with curl**:
```bash
curl -X POST 'https://your-project.supabase.co/functions/v1/send-push-notification' \
  -H 'Authorization: Bearer YOUR_SUPABASE_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "device_token": "test-token",
    "title": "Test Notification",
    "body": "This is a test message"
  }'
```

## 🔧 Troubleshooting

### Common Issues:

1. **"Firebase service account not configured"**
   - Make sure you've set the `FIREBASE_SERVICE_ACCOUNT` environment variable
   - Verify the JSON is valid and complete

2. **"Authentication failed"**
   - Check that the service account has the correct permissions
   - Ensure the JSON format is correct

3. **"Project not found"**
   - Verify the `project_id` in the service account matches your Firebase project

### Debug Steps:

1. **Check Environment Variable**:
```bash
supabase secrets list
```

2. **Validate JSON**:
   - Use an online JSON validator to check your service account JSON

3. **Check Logs**:
```bash
supabase functions logs send-push-notification
```

## 🎯 What's Different from Server Key?

| Legacy Server Key | Modern Service Account |
|------------------|------------------------|
| Simple string | JSON with private key |
| Less secure | More secure with OAuth2 |
| Being deprecated | Current standard |
| Limited permissions | Granular permissions |
| No expiration | Can be rotated |

## 📚 Additional Resources

- [Firebase Admin SDK Documentation](https://firebase.google.com/docs/admin/setup)
- [Google Service Account Guide](https://cloud.google.com/iam/docs/service-accounts)
- [FCM Server Documentation](https://firebase.google.com/docs/cloud-messaging/server)

The service account approach is more secure and is the recommended way to authenticate with Firebase services from server environments like Supabase Edge Functions.
