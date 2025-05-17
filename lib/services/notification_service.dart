import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/models/chat_message.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'package:pulsemeet/services/pulse_participant_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;

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
  Future<void> showMessageNotification(ChatMessage message) async {
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
      case 'text':
        notificationBody = message.content.length > 50
            ? '${message.content.substring(0, 47)}...'
            : message.content;
        break;
      case 'image':
        notificationBody = message.content.isNotEmpty
            ? 'Sent an image: ${message.content}'
            : 'Sent an image';
        break;
      case 'video':
        notificationBody = message.content.isNotEmpty
            ? 'Sent a video: ${message.content}'
            : 'Sent a video';
        break;
      case 'audio':
        notificationBody = message.content.isNotEmpty
            ? 'Sent a voice message: ${message.content}'
            : 'Sent a voice message';
        break;
      case 'location':
        notificationBody = message.content.isNotEmpty
            ? 'Shared a location: ${message.content}'
            : 'Shared a location';
        break;
      case 'live_location':
        notificationBody = message.content.isNotEmpty
            ? 'Started sharing live location: ${message.content}'
            : 'Started sharing live location';
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
      payload: 'message:${message.pulseId}',
    );
  }

  /// Show a mention notification
  Future<void> showMentionNotification(
      ChatMessage message, String username) async {
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
      payload: 'mention:${message.pulseId}:${message.id}',
    );
  }

  /// Process mentions in a message and send notifications
  Future<void> processMentions(ChatMessage message) async {
    // Get mentions from the message
    final mentions = message.getMentions();
    if (mentions.isEmpty) return;

    // Get participants
    final participants =
        await _participantService.getParticipants(message.pulseId);

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
}
