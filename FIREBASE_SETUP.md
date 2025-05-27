# Firebase Push Notifications Setup Guide

This guide will help you set up Firebase Cloud Messaging (FCM) for real-time push notifications in PulseMeet using the modern Firebase Admin SDK (no legacy server key needed).

## 🔥 Firebase Project Setup

### 1. Create Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Create a project" or "Add project"
3. Enter project name: `pulsemeet-notifications`
4. Enable Google Analytics (optional)
5. Click "Create project"

### 2. Add Android App
1. In Firebase Console, click "Add app" → Android
2. Enter package name: `com.example.pulsemeet`
3. Enter app nickname: `PulseMeet Android`
4. Download `google-services.json`
5. Place the file in `android/app/google-services.json`

### 3. Add iOS App
1. In Firebase Console, click "Add app" → iOS
2. Enter bundle ID: `com.example.pulsemeet`
3. Enter app nickname: `PulseMeet iOS`
4. Download `GoogleService-Info.plist`
5. Place the file in `ios/Runner/GoogleService-Info.plist`

### 4. Generate Service Account Key (Instead of Server Key)
1. In Firebase Console, go to **Project Settings** (gear icon)
2. Click on **Service accounts** tab
3. Click **Generate new private key**
4. Download the JSON file (this contains your service account credentials)
5. **Important**: Keep this file secure and never commit it to version control

## 📱 Platform Configuration

### Android Configuration

1. **Update `android/build.gradle`:**
```gradle
buildscript {
    dependencies {
        classpath 'com.google.gms:google-services:4.3.15'
    }
}
```

2. **Update `android/app/build.gradle`:**
```gradle
apply plugin: 'com.google.gms.google-services'

android {
    compileSdkVersion 34

    defaultConfig {
        minSdkVersion 24  // Required for Firebase Messaging
        targetSdkVersion 34
    }
}

dependencies {
    implementation 'com.google.firebase:firebase-messaging:23.2.1'
}
```

3. **Update `android/app/src/main/AndroidManifest.xml`:**
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.VIBRATE" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application>
        <!-- Firebase Messaging Service -->
        <service
            android:name="io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService"
            android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT" />
            </intent-filter>
        </service>

        <!-- Notification metadata -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@drawable/ic_launcher" />
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_color"
            android:resource="@color/notification_color" />
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="pulsemeet_messages" />
    </application>
</manifest>
```

### iOS Configuration

1. **Update `ios/Runner/Info.plist`:**
```xml
<key>UIBackgroundModes</key>
<array>
    <string>background-fetch</string>
    <string>remote-notification</string>
</array>
```

2. **Enable Push Notifications in Xcode:**
   - Open `ios/Runner.xcworkspace` in Xcode
   - Select Runner target
   - Go to "Signing & Capabilities"
   - Click "+ Capability"
   - Add "Push Notifications"
   - Add "Background Modes" (if not already added)
   - Check "Remote notifications" under Background Modes

## 🔑 Service Account Configuration

### 1. Configure Supabase Environment
Add the Firebase service account to your Supabase project:

1. Go to Supabase Dashboard → Settings → Environment Variables
2. Add new variable:
   - Name: `FIREBASE_SERVICE_ACCOUNT`
   - Value: `[Entire contents of your service account JSON file]`

**Example service account JSON structure:**
```json
{
  "type": "service_account",
  "project_id": "your-project-id",
  "private_key_id": "key-id",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "firebase-adminsdk-xxxxx@your-project-id.iam.gserviceaccount.com",
  "client_id": "123456789",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-xxxxx%40your-project-id.iam.gserviceaccount.com"
}
```

**⚠️ Security Note**: Copy the entire JSON content as a single line string into the environment variable.

### 3. Deploy Edge Function
Deploy the push notification Edge Function:

```bash
supabase functions deploy send-push-notification
```

## 🗄️ Database Setup

The user_devices table will be automatically created when you run the app. It stores:
- User device tokens
- Device types (iOS/Android)
- Active status
- Last seen timestamps

## 🧪 Testing Push Notifications

### 1. Test with Firebase Console
1. Go to Firebase Console → Cloud Messaging
2. Click "Send your first message"
3. Enter notification title and text
4. Select your app
5. Send test message

### 2. Test with App
1. Run the app on a physical device
2. Grant notification permissions
3. Send a message from another user
4. Verify notification appears

## 🔧 Troubleshooting

### Common Issues

1. **Notifications not received:**
   - Check device permissions
   - Verify Firebase configuration files
   - Check Supabase Edge Function logs
   - Ensure device token is stored in database

2. **Android build errors:**
   - Update minSdkVersion to 24+
   - Add google-services plugin
   - Check gradle dependencies

3. **iOS build errors:**
   - Add Push Notifications capability
   - Check bundle ID matches Firebase
   - Verify GoogleService-Info.plist is added

### Debug Commands

```bash
# Check Flutter dependencies
flutter pub deps

# Clean and rebuild
flutter clean
flutter pub get

# Check Android build
flutter build apk --debug

# Check iOS build
flutter build ios --debug
```

## 📊 Monitoring

### Firebase Console
- Monitor message delivery rates
- View device registration statistics
- Check error logs

### Supabase Dashboard
- Monitor Edge Function invocations
- Check user_devices table data
- View real-time subscriptions

## 🔒 Security Considerations

1. **Never expose server keys in client code**
2. **Use Supabase Edge Functions for server-side operations**
3. **Implement proper RLS policies**
4. **Validate user permissions before sending notifications**
5. **Clean up inactive device tokens regularly**

## 🚀 Production Deployment

1. **Update package names and bundle IDs**
2. **Generate production Firebase configuration**
3. **Set up proper APNs certificates for iOS**
4. **Configure production Supabase environment**
5. **Test thoroughly on physical devices**

## 📝 Environment Variables

Required environment variables:
- `FIREBASE_SERVICE_ACCOUNT`: Complete Firebase service account JSON (as string)
- `SUPABASE_URL`: Your Supabase project URL
- `SUPABASE_ANON_KEY`: Your Supabase anonymous key

## 🎯 Features Implemented

✅ **Real-time push notifications**
✅ **Message content preview**
✅ **Notification grouping by conversation**
✅ **Sound and vibration controls**
✅ **Quiet hours functionality**
✅ **Privacy controls**
✅ **Cross-platform support (Android/iOS)**
✅ **Background message handling**
✅ **Device token management**
✅ **Automatic cleanup of inactive devices**

The push notification system is now fully integrated with PulseMeet's existing real-time message detection system and will provide instant notifications similar to WhatsApp's behavior!
