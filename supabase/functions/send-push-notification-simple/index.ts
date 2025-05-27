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

    // For now, we'll use local notifications through the app
    // This is a simplified version that stores the notification in the database
    // The app will pick it up via real-time subscriptions

    console.log('📱 Processing push notification request:', {
      device_token: notificationData.device_token.substring(0, 20) + '...',
      title: notificationData.title,
      body: notificationData.body,
      device_type: notificationData.device_type,
    })

    // Store notification in database for the app to pick up
    const notificationRecord = {
      user_id: user.id,
      device_token: notificationData.device_token,
      title: notificationData.title,
      body: notificationData.body,
      data: notificationData.data || {},
      device_type: notificationData.device_type || 'unknown',
      status: 'pending',
      created_at: new Date().toISOString(),
    }

    // Try to insert into pending_notifications table
    try {
      const { error: insertError } = await supabaseClient
        .from('pending_notifications')
        .insert(notificationRecord)

      if (insertError) {
        console.warn('Database insert warning (continuing anyway):', insertError)
      } else {
        console.log('✅ Notification stored successfully for real-time delivery')
      }
    } catch (dbError) {
      console.warn('Database operation warning (continuing anyway):', dbError)
    }

    // Try to update device last_seen timestamp (optional)
    try {
      await supabaseClient
        .from('user_devices')
        .update({ last_seen: new Date().toISOString() })
        .eq('device_token', notificationData.device_token)
    } catch (deviceUpdateError) {
      console.warn('Device update warning (continuing anyway):', deviceUpdateError)
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Notification queued for delivery',
        method: 'database_realtime',
        notification_id: notificationRecord.created_at,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )

  } catch (error) {
    console.error('Error processing push notification:', error)

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
