import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface NotificationRequest {
  device_token: string
  device_type?: string
  title: string
  body: string
  data?: Record<string, any>
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get the authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      throw new Error('No authorization header')
    }

    // Create Supabase client
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    )

    // Verify the user is authenticated
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
    if (authError || !user) {
      throw new Error('Unauthorized')
    }

    // Parse the request body
    const notificationData: NotificationRequest = await req.json()

    // Validate required fields
    if (!notificationData.device_token || !notificationData.title || !notificationData.body) {
      throw new Error('Missing required fields: device_token, title, body')
    }

    // Get Firebase service account from environment
    const firebaseServiceAccount = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!firebaseServiceAccount) {
      throw new Error('Firebase service account not configured')
    }

    // Parse the service account JSON
    const serviceAccount = JSON.parse(firebaseServiceAccount)

    // Prepare FCM payload
    const fcmPayload = {
      to: notificationData.device_token,
      notification: {
        title: notificationData.title,
        body: notificationData.body,
        icon: 'ic_launcher',
        sound: 'default',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      data: notificationData.data || {},
      priority: 'high',
      content_available: true,
    }

    // Add platform-specific configurations
    if (notificationData.device_type === 'ios') {
      fcmPayload['apns'] = {
        payload: {
          aps: {
            alert: {
              title: notificationData.title,
              body: notificationData.body,
            },
            badge: 1,
            sound: 'default',
            'content-available': 1,
          },
        },
      }
    } else if (notificationData.device_type === 'android') {
      fcmPayload['android'] = {
        notification: {
          title: notificationData.title,
          body: notificationData.body,
          icon: 'ic_launcher',
          sound: 'default',
          channel_id: 'pulsemeet_messages',
        },
        priority: 'high',
        ttl: '86400s', // 24 hours
      }
    }

    // Generate JWT for Firebase Admin SDK
    const accessToken = await getFirebaseAccessToken(serviceAccount)

    // Use the new FCM v1 API
    const projectId = serviceAccount.project_id
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

    // Prepare FCM v1 payload
    const fcmV1Payload = {
      message: {
        token: notificationData.device_token,
        notification: {
          title: notificationData.title,
          body: notificationData.body,
        },
        data: notificationData.data || {},
        android: notificationData.device_type === 'android' ? {
          notification: {
            channel_id: 'pulsemeet_messages',
            sound: 'default',
          },
          priority: 'high',
        } : undefined,
        apns: notificationData.device_type === 'ios' ? {
          payload: {
            aps: {
              alert: {
                title: notificationData.title,
                body: notificationData.body,
              },
              badge: 1,
              sound: 'default',
              'content-available': 1,
            },
          },
        } : undefined,
      },
    }

    // Send FCM notification using v1 API
    const fcmResponse = await fetch(fcmUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(fcmV1Payload),
    })

    const fcmResult = await fcmResponse.json()

    if (!fcmResponse.ok) {
      console.error('FCM Error:', fcmResult)
      throw new Error(`FCM request failed: ${fcmResult.error || 'Unknown error'}`)
    }

    // Check if the notification was successful
    if (fcmResult.failure > 0) {
      console.error('FCM Failure:', fcmResult.results)

      // Handle invalid tokens
      if (fcmResult.results && fcmResult.results[0] && fcmResult.results[0].error) {
        const error = fcmResult.results[0].error
        if (error === 'InvalidRegistration' || error === 'NotRegistered') {
          // Mark the device token as inactive
          await supabaseClient
            .from('user_devices')
            .update({ is_active: false })
            .eq('device_token', notificationData.device_token)

          console.log('Marked invalid device token as inactive:', notificationData.device_token)
        }
      }

      throw new Error(`FCM notification failed: ${fcmResult.results[0]?.error || 'Unknown error'}`)
    }

    // Log successful notification
    console.log('FCM notification sent successfully:', {
      device_token: notificationData.device_token.substring(0, 20) + '...',
      title: notificationData.title,
      success: fcmResult.success,
      multicast_id: fcmResult.multicast_id,
    })

    // Update device last_seen timestamp
    await supabaseClient
      .from('user_devices')
      .update({ last_seen: new Date().toISOString() })
      .eq('device_token', notificationData.device_token)

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Notification sent successfully',
        fcm_response: {
          success: fcmResult.success,
          failure: fcmResult.failure,
          multicast_id: fcmResult.multicast_id,
        },
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )

  } catch (error) {
    console.error('Error sending push notification:', error)

    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
})

// Helper function to generate Firebase access token using service account
async function getFirebaseAccessToken(serviceAccount: any): Promise<string> {
  // For Deno environment, we'll use a simpler approach with the Google Auth API
  // This is a simplified version - in production, you might want to use a proper JWT library

  try {
    // Use Google's token endpoint with service account
    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: await createJWT(serviceAccount),
      }),
    })

    const tokenResult = await tokenResponse.json()

    if (!tokenResponse.ok) {
      throw new Error(`Failed to get access token: ${JSON.stringify(tokenResult)}`)
    }

    return tokenResult.access_token
  } catch (error) {
    console.error('Error getting Firebase access token:', error)
    throw new Error(`Authentication failed: ${error.message}`)
  }
}

// Create JWT for service account authentication
async function createJWT(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const expiry = now + 3600 // 1 hour

  const header = {
    alg: 'RS256',
    typ: 'JWT',
  }

  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: expiry,
  }

  // Base64URL encode header and payload
  const encodedHeader = base64UrlEncode(JSON.stringify(header))
  const encodedPayload = base64UrlEncode(JSON.stringify(payload))
  const signatureInput = `${encodedHeader}.${encodedPayload}`

  // For Deno, we'll use the Web Crypto API
  const privateKeyPem = serviceAccount.private_key.replace(/\\n/g, '\n')

  // Import the private key
  const privateKey = await importPrivateKey(privateKeyPem)

  // Sign the JWT
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(signatureInput)
  )

  const encodedSignature = base64UrlEncode(new Uint8Array(signature))
  return `${signatureInput}.${encodedSignature}`
}

// Helper function to import private key
async function importPrivateKey(pemKey: string): Promise<CryptoKey> {
  // Remove PEM headers and decode base64
  const pemContents = pemKey
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '')

  const keyData = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0))

  return await crypto.subtle.importKey(
    'pkcs8',
    keyData,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  )
}

// Base64URL encoding helper
function base64UrlEncode(data: string | Uint8Array): string {
  let base64: string

  if (typeof data === 'string') {
    base64 = btoa(data)
  } else {
    base64 = btoa(String.fromCharCode(...data))
  }

  return base64
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')
}
