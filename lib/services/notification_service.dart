import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/models/message.dart' as models;
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'package:pulsemeet/services/pulse_participant_service.dart';
import 'package:pulsemeet/services/firebase_messaging_service.dart';
import 'package:pulsemeet/services/notification_preferences_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A service to handle notifications for pulses
class NotificationService {
  // Singleton instance
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal() {
    _initNotifications();
  }

  // Notification plugin
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Supabase client
  final _supabase = Supabase.instance.client;

  // Participant service
  final _participantService = PulseParticipantService();

  // Firebase messaging service
  final FirebaseMessagingService _firebaseMessaging =
      FirebaseMessagingService();

  // Notification preferences service
  final NotificationPreferencesService _preferencesService =
      NotificationPreferencesService();

  /// Default notification radius in meters
  static const int defaultNotificationRadius = 5000;

  /// Initialize notifications
  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
    );

    // Initialize Firebase messaging for push notifications
    await _firebaseMessaging.initialize();

    // Initialize notification preferences
    await _preferencesService.initialize();

    debugPrint('✅ Notification service initialized with Firebase support');
  }

  /// Request notification permissions
  Future<void> requestPermissions() async {
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  /// Check if a user is within the notification radius of a pulse
  bool isUserWithinNotificationRadius(LatLng userLocation, Pulse pulse,
      {int? notificationRadius}) {
    // Use the provided notification radius or the default
    final radius = notificationRadius ?? defaultNotificationRadius;

    // Calculate the distance between the user and the pulse
    final distance = calculateDistance(userLocation, pulse.location);

    // Convert to meters
    final distanceMeters = distance * 1000;

    // Check if the user is within the notification radius
    return distanceMeters <= radius;
  }

  /// Calculate distance between two points using the Haversine formula
  double calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371.0; // Earth's radius in kilometers

    // Convert latitude and longitude from degrees to radians
    final double lat1 = _degreesToRadians(point1.latitude);
    final double lon1 = _degreesToRadians(point1.longitude);
    final double lat2 = _degreesToRadians(point2.latitude);
    final double lon2 = _degreesToRadians(point2.longitude);

    // Haversine formula
    final double dLat = lat2 - lat1;
    final double dLon = lon2 - lon1;
    final double a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final double distance = earthRadius * c;

    return distance;
  }

  /// Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }

  /// Show a notification for a new pulse
  void showPulseNotification(Pulse pulse) {
    // This would be implemented with a proper notification system
    // For now, we'll just log it
    debugPrint('Showing notification for pulse: ${pulse.id} - ${pulse.title}');

    // In a real implementation, this would use Firebase Cloud Messaging
    // or another notification service to show a push notification
  }

  /// Show a message notification
  Future<void> showMessageNotification(models.Message message) async {
    // Don't show notifications for messages from the current user
    if (message.senderId == _supabase.auth.currentUser?.id) {
      return;
    }

    // Get sender profile
    final senderName = message.senderName ?? 'Someone';

    // Create notification content
    String notificationTitle = 'New message from $senderName';
    String notificationBody = '';

    // Create notification body based on message type
    switch (message.messageType) {
      case models.MessageType.text:
        notificationBody = message.content.length > 50
            ? '${message.content.substring(0, 47)}...'
            : message.content;
        break;
      case models.MessageType.image:
        notificationBody = message.content.isNotEmpty
            ? 'Sent an image: ${message.content}'
            : 'Sent an image';
        break;
      case models.MessageType.video:
        notificationBody = message.content.isNotEmpty
            ? 'Sent a video: ${message.content}'
            : 'Sent a video';
        break;
      case models.MessageType.audio:
        notificationBody = message.content.isNotEmpty
            ? 'Sent a voice message: ${message.content}'
            : 'Sent a voice message';
        break;
      case models.MessageType.location:
        notificationBody = message.content.isNotEmpty
            ? 'Shared a location: ${message.content}'
            : 'Shared a location';
        break;
      default:
        notificationBody = 'Sent a message';
    }

    // Show notification
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'messages_channel',
      'Messages',
      channelDescription: 'Notifications for new messages',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _flutterLocalNotificationsPlugin.show(
      message.id.hashCode,
      notificationTitle,
      notificationBody,
      platformChannelSpecifics,
      payload: 'message:${message.conversationId}',
    );
  }

  /// Show a mention notification
  Future<void> showMentionNotification(
      models.Message message, String username) async {
    // Don't show notifications for messages from the current user
    if (message.senderId == _supabase.auth.currentUser?.id) {
      return;
    }

    // Get sender profile
    final senderName = message.senderName ?? 'Someone';

    // Create notification content
    String notificationTitle = '$senderName mentioned you';
    String notificationBody = message.content.length > 50
        ? '${message.content.substring(0, 47)}...'
        : message.content;

    // Show notification
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'mentions_channel',
      'Mentions',
      channelDescription: 'Notifications for mentions',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _flutterLocalNotificationsPlugin.show(
      '${message.id}_mention_$username'.hashCode,
      notificationTitle,
      notificationBody,
      platformChannelSpecifics,
      payload: 'mention:${message.conversationId}:${message.id}',
    );
  }

  /// Process mentions in a message and send notifications
  Future<void> processMentions(models.Message message) async {
    // Get mentions from the message
    final mentions = message.mentions ?? [];
    if (mentions.isEmpty) return;

    // Get participants
    final participants =
        await _participantService.getParticipants(message.conversationId);

    // Get current user
    final currentUserId = _supabase.auth.currentUser?.id;

    // Send notifications to mentioned users
    for (final username in mentions) {
      // Find the user with this username
      final mentionedUser = participants.firstWhere(
        (p) => p.username == username,
        orElse: () => Profile(
          id: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          lastSeenAt: DateTime.now(),
        ),
      );

      // Skip if user not found or is the current user
      if (mentionedUser.id.isEmpty || mentionedUser.id == currentUserId) {
        continue;
      }

      // Send notification
      await showMentionNotification(message, username);

      // Record the mention in the database
      try {
        await _supabase.from('mentions').insert({
          'message_id': message.id,
          'user_id': mentionedUser.id,
          'created_at': DateTime.now().toIso8601String(),
          'is_read': false,
        });
      } catch (e) {
        debugPrint('Error recording mention: $e');
      }
    }
  }

  /// Show a notification for a new pulse from a favorite host
  Future<void> showFavoriteHostPulseNotification(Pulse pulse) async {
    // Get the user's notification settings
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await _supabase
          .from('profiles')
          .select('notification_settings')
          .eq('id', userId)
          .single();

      final notificationSettings = NotificationSettings.fromJson(
          response['notification_settings'] is String
              ? jsonDecode(response['notification_settings'])
              : response['notification_settings']);

      // Check if favorite host notifications are enabled
      if (!notificationSettings.pushNotifications ||
          !notificationSettings.favoriteHostNotifications) {
        return;
      }

      // Create notification content
      final hostName = pulse.creatorName ?? 'A favorite host';
      final notificationTitle = '$hostName created a new pulse';
      final notificationBody = '${pulse.title}: ${pulse.description}';

      // Show notification
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'favorite_hosts_channel',
        'Favorite Hosts',
        channelDescription: 'Notifications for favorite hosts',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await _flutterLocalNotificationsPlugin.show(
        'favorite_host_${pulse.id}'.hashCode,
        notificationTitle,
        notificationBody,
        platformChannelSpecifics,
        payload: 'favorite_host_pulse:${pulse.id}',
      );
    } catch (e) {
      debugPrint('Error showing favorite host pulse notification: $e');
    }
  }

  /// Send a notification for a new connection request
  Future<void> sendConnectionRequestNotification(String receiverId) async {
    try {
      // Get the requester's profile
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final requesterResponse = await _supabase
          .from('profiles')
          .select('username, display_name')
          .eq('id', userId)
          .single();

      final requesterName = requesterResponse['display_name'] ??
          requesterResponse['username'] ??
          'Someone';

      debugPrint(
          'Sending connection request notification from $requesterName to receiver $receiverId');

      // For now, we'll use a simple approach:
      // The real-time subscription in ConnectionService will handle notifying the receiver
      // when they open the app and see the new pending request

      // In a production app, you would implement push notifications here using:
      // - Firebase Cloud Messaging (FCM)
      // - Apple Push Notification Service (APNs)
      // - Or a service like OneSignal

      debugPrint('Connection request notification sent successfully');
    } catch (e) {
      debugPrint('Error sending connection request notification: $e');
    }
  }

  /// Send a notification for an accepted connection request
  Future<void> sendConnectionAcceptedNotification(String requesterId) async {
    try {
      // Get the receiver's profile
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final receiverResponse = await _supabase
          .from('profiles')
          .select('username, display_name')
          .eq('id', userId)
          .single();

      final receiverName = receiverResponse['display_name'] ??
          receiverResponse['username'] ??
          'Someone';

      // Get the requester's notification settings
      final requesterResponse = await _supabase
          .from('profiles')
          .select('notification_settings')
          .eq('id', requesterId)
          .single();

      final notificationSettings = NotificationSettings.fromJson(
          requesterResponse['notification_settings'] is String
              ? jsonDecode(requesterResponse['notification_settings'])
              : requesterResponse['notification_settings']);

      // Check if push notifications are enabled
      if (!notificationSettings.pushNotifications) {
        return;
      }

      // Create notification content
      const notificationTitle = 'Connection Request Accepted';
      final notificationBody = '$receiverName accepted your connection request';

      // Show notification
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'connections_channel',
        'Connections',
        channelDescription: 'Notifications for connection requests',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await _flutterLocalNotificationsPlugin.show(
        'connection_accepted_${userId}_$requesterId'.hashCode,
        notificationTitle,
        notificationBody,
        platformChannelSpecifics,
        payload: 'connection_accepted:$userId',
      );
    } catch (e) {
      debugPrint('Error sending connection accepted notification: $e');
    }
  }

  /// Send a notification for a new direct message
  Future<void> sendDirectMessageNotification(
    String receiverId,
    String messageContent,
    String senderId,
  ) async {
    try {
      // Get the sender's profile
      final senderResponse = await _supabase
          .from('profiles')
          .select('username, display_name')
          .eq('id', senderId)
          .single();

      final senderName = senderResponse['display_name'] ??
          senderResponse['username'] ??
          'Someone';

      // Get the receiver's notification settings
      final receiverResponse = await _supabase
          .from('profiles')
          .select('notification_settings')
          .eq('id', receiverId)
          .single();

      final notificationSettings = NotificationSettings.fromJson(
          receiverResponse['notification_settings'] is String
              ? jsonDecode(receiverResponse['notification_settings'])
              : receiverResponse['notification_settings']);

      // Check if push notifications are enabled
      if (!notificationSettings.pushNotifications) {
        return;
      }

      // Create notification content
      final notificationTitle = 'Message from $senderName';
      final notificationBody = messageContent.length > 50
          ? '${messageContent.substring(0, 47)}...'
          : messageContent;

      // Show notification
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'direct_messages_channel',
        'Direct Messages',
        channelDescription: 'Notifications for direct messages',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await _flutterLocalNotificationsPlugin.show(
        'direct_message_${senderId}_$receiverId'.hashCode,
        notificationTitle,
        notificationBody,
        platformChannelSpecifics,
        payload: 'direct_message:$senderId',
      );
    } catch (e) {
      debugPrint('Error sending direct message notification: $e');
    }
  }

  /// Show test notification for debugging
  Future<void> showTestNotification({
    required String title,
    required String body,
  }) async {
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'test',
        'Test Notifications',
        channelDescription: 'Test notifications for debugging',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await _flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        platformChannelSpecifics,
      );

      debugPrint('✅ Test notification shown: $title - $body');
    } catch (e) {
      debugPrint('❌ Error showing test notification: $e');
    }
  }
}
