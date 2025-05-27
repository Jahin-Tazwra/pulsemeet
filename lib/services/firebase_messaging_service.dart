import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../models/message.dart';
import '../models/conversation.dart';
import '../screens/chat/chat_screen.dart';
import '../main.dart';
import 'notification_preferences_service.dart';

/// Firebase Cloud Messaging service for real-time push notifications
class FirebaseMessagingService {
  static final FirebaseMessagingService _instance =
      FirebaseMessagingService._internal();
  factory FirebaseMessagingService() => _instance;
  FirebaseMessagingService._internal();

  // Services
  FirebaseMessaging? _firebaseMessaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final SupabaseClient _supabase = Supabase.instance.client;
  final NotificationPreferencesService _preferencesService =
      NotificationPreferencesService();

  // State
  bool _isInitialized = false;
  String? _fcmToken;

  // Persistent notification grouping - tracks all unseen messages until conversation is opened
  final Map<String, List<Map<String, dynamic>>> _groupedNotifications = {};
  final Map<String, DateTime> _lastNotificationTime = {};
  final Map<String, Set<String>> _seenMessageIds =
      {}; // Track which messages have been seen

  // Track current active conversation to suppress notifications
  String? _currentActiveConversationId;

  // Constants
  static const String _fcmTokenKey = 'fcm_token';
  static const String _notificationChannelId = 'pulsemeet_messages';
  static const String _notificationChannelName = 'PulseMeet Messages';
  static const String _notificationChannelDescription =
      'Real-time message notifications';

  /// Reset initialization state (for debugging)
  void resetInitialization() {
    _isInitialized = false;
    debugPrint('🔄 Firebase Messaging Service initialization reset');
  }

  /// Initialize Firebase Messaging service
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⚠️ Firebase Messaging Service already initialized, skipping');
      return;
    }

    try {
      debugPrint('🔥 Initializing Firebase Messaging Service...');

      // Initialize Firebase if not already done
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
        debugPrint('🔥 Firebase Core initialized');
      }

      // Initialize Firebase Messaging
      _firebaseMessaging = FirebaseMessaging.instance;

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Request permissions
      await _requestPermissions();

      // Get and store FCM token
      debugPrint('🔔 About to initialize FCM token...');
      await _initializeFCMToken();
      debugPrint('🔔 FCM token initialization completed');

      // Set up message handlers
      debugPrint('🔔 About to call _setupMessageHandlers()...');
      debugPrint('🔔 Firebase messaging instance: $_firebaseMessaging');
      _setupMessageHandlers();
      debugPrint('🔔 _setupMessageHandlers() call completed');

      // Initialize notification preferences
      debugPrint('🔔 About to initialize notification preferences...');
      await _preferencesService.initialize();
      debugPrint('🔔 Notification preferences initialization completed');

      _isInitialized = true;
      debugPrint('✅ Firebase Messaging Service initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing Firebase Messaging Service: $e');
      // Continue without push notifications if Firebase fails
      _isInitialized = false;
    }
  }

  /// Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
      requestCriticalPermission: false,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channel for Android
    if (Platform.isAndroid) {
      await _createNotificationChannel();
    }
  }

  /// Create Android notification channel
  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: _notificationChannelDescription,
      importance: Importance.high,
      enableVibration: true,
      enableLights: true,
      ledColor: Colors.blue,
      showBadge: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(channel);
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    if (_firebaseMessaging == null) return;

    // Request FCM permissions
    final NotificationSettings settings =
        await _firebaseMessaging!.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('🔔 FCM Permission status: ${settings.authorizationStatus}');

    // For iOS, also request local notification permissions
    if (Platform.isIOS) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    // For Android 13+, request notification permission
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  /// Initialize and store FCM token
  Future<void> _initializeFCMToken() async {
    if (_firebaseMessaging == null) return;

    try {
      // Get FCM token
      _fcmToken = await _firebaseMessaging!.getToken();

      if (_fcmToken != null) {
        debugPrint('🔑 FCM Token obtained: ${_fcmToken!.substring(0, 20)}...');

        // Store token locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_fcmTokenKey, _fcmToken!);

        // Store token in Supabase for server-side notifications
        await _storeFCMTokenInDatabase();

        // Listen for token refresh
        _firebaseMessaging!.onTokenRefresh.listen(_onTokenRefresh);
      }
    } catch (e) {
      debugPrint('❌ Error getting FCM token: $e');
    }
  }

  /// Store FCM token in Supabase database
  Future<void> _storeFCMTokenInDatabase() async {
    if (_fcmToken == null) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Store or update FCM token in user_devices table
      await _supabase.from('user_devices').upsert({
        'user_id': userId,
        'device_token': _fcmToken,
        'device_type': Platform.isIOS ? 'ios' : 'android',
        'is_active': true,
        'last_seen': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ FCM token stored in database');
    } catch (e) {
      debugPrint('❌ Error storing FCM token in database: $e');
    }
  }

  /// Handle FCM token refresh
  Future<void> _onTokenRefresh(String newToken) async {
    debugPrint('🔄 FCM Token refreshed');
    _fcmToken = newToken;

    // Update stored token
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fcmTokenKey, newToken);

    // Update database
    await _storeFCMTokenInDatabase();
  }

  /// Set up Firebase message handlers
  void _setupMessageHandlers() {
    debugPrint('🔔 Setting up Firebase message handlers...');
    if (_firebaseMessaging == null) {
      debugPrint('❌ Firebase messaging is null, cannot set up handlers');
      return;
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background messages (when app is backgrounded but not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

    // Handle messages when app is terminated (handled by background handler)
    _firebaseMessaging!.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _handleBackgroundMessage(message);
      }
    });

    // Set up real-time listener for pending notifications from Edge Function
    debugPrint('🔔 About to set up pending notifications listener...');
    _setupPendingNotificationsListener();
  }

  /// Set up real-time listener for pending notifications
  void _setupPendingNotificationsListener() {
    try {
      debugPrint(
          '🔔 Setting up real-time listener for pending notifications...');

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint(
            '⚠️ No authenticated user, skipping pending notifications listener');
        return;
      }

      debugPrint('🔔 Setting up listener for user: $userId');

      // Listen for new notifications in the pending_notifications table
      final channel =
          Supabase.instance.client.channel('pending_notifications_$userId');

      channel.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(
          event: 'INSERT',
          schema: 'public',
          table: 'pending_notifications',
          filter: 'user_id=eq.$userId',
        ),
        (payload, [ref]) async {
          debugPrint('🔔 Real-time notification received from Edge Function');
          debugPrint('🔔 Payload: $payload');
          debugPrint(
              '🔔 About to call _handlePendingNotification with WhatsApp-style grouping...');
          await _handlePendingNotification(payload['new']);
          debugPrint('🔔 _handlePendingNotification completed');
        },
      );

      // Subscribe to the channel
      channel.subscribe();
      debugPrint('✅ Pending notifications listener set up successfully');
    } catch (e) {
      debugPrint('❌ Error setting up pending notifications listener: $e');
    }
  }

  /// Handle pending notification from database
  Future<void> _handlePendingNotification(
      Map<String, dynamic>? notificationData) async {
    if (notificationData == null) {
      debugPrint('⚠️ Received null notification data');
      return;
    }

    try {
      debugPrint(
          '📱 Processing pending notification: ${notificationData['title']}');
      debugPrint('📱 Full notification data: $notificationData');

      final title = notificationData['title'] as String? ?? 'PulseMeet';
      final body = notificationData['body'] as String? ?? 'New notification';
      final data = notificationData['data'] as Map<String, dynamic>? ?? {};
      final dbNotificationId = notificationData['id'] as String?;

      debugPrint(
          '📱 Parsed notification: title=$title, body=$body, id=$dbNotificationId');

      // CRITICAL FIX: Check if this is a message notification that should use WhatsApp-style grouping
      if (data['type'] == 'message' && data['conversation_id'] != null) {
        debugPrint(
            '🔔 Message notification detected - using WhatsApp-style grouping');

        final conversationId = data['conversation_id'] as String;
        final messageId = data['message_id'] as String? ??
            'unknown_${DateTime.now().millisecondsSinceEpoch}';
        final senderId = data['sender_id'] as String? ?? 'unknown';
        final senderName = data['sender_name'] as String? ?? title;
        final messageContent = data['message_content'] as String? ?? body;
        final messageType = data['message_type'] as String? ?? 'text';
        final senderAvatarUrl = data['sender_avatar_url'] as String?;

        // Don't show notifications for own messages
        final currentUserId = _supabase.auth.currentUser?.id;
        if (senderId == currentUserId) {
          debugPrint('🚫 Skipping notification for own message');
          await _markNotificationAsDelivered(dbNotificationId);
          return;
        }

        // Check if user is currently viewing this conversation
        if (_currentActiveConversationId == conversationId) {
          debugPrint(
              '👁️ User is currently viewing conversation $conversationId, suppressing notification');
          await _markNotificationAsDelivered(dbNotificationId);
          return;
        }

        // Use the WhatsApp-style grouping flow
        await _addToNotificationGroup(conversationId, {
          'message_id': messageId,
          'sender_id': senderId,
          'sender_name': senderName,
          'sender_avatar_url': senderAvatarUrl,
          'content': messageContent,
          'type': messageType,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        await _showGroupedNotification(conversationId);
        debugPrint(
            '✅ WhatsApp-style grouped notification shown for conversation: $conversationId');
      } else {
        // Non-message notifications (pulses, etc.) - use the old direct method
        debugPrint('📱 Non-message notification - using direct display');
        final localNotificationId =
            DateTime.now().millisecondsSinceEpoch % 2147483647;
        await _showLocalNotification(
          id: localNotificationId,
          title: title,
          body: body,
          payload: jsonEncode({
            'type': 'push_notification',
            'data': data,
          }),
        );
      }

      // Mark notification as delivered
      await _markNotificationAsDelivered(dbNotificationId);

      debugPrint('✅ Pending notification processed successfully');
    } catch (e) {
      debugPrint('❌ Error processing pending notification: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
    }
  }

  /// Mark notification as delivered in database
  Future<void> _markNotificationAsDelivered(String? notificationId) async {
    if (notificationId == null) return;

    try {
      await Supabase.instance.client.from('pending_notifications').update({
        'status': 'delivered',
        'delivered_at': DateTime.now().toIso8601String(),
      }).eq('id', notificationId);

      debugPrint('✅ Notification marked as delivered: $notificationId');
    } catch (e) {
      debugPrint('❌ Error marking notification as delivered: $e');
    }
  }

  /// Handle foreground messages (app is active)
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('🔔 Received foreground message: ${message.messageId}');

    // Check if notifications are enabled
    if (!await _preferencesService.areNotificationsEnabled()) {
      debugPrint('🔕 Notifications disabled, skipping');
      return;
    }

    // Check connectivity
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) {
      debugPrint('📵 No internet connection, skipping notification');
      return;
    }

    // Process the message
    await _processIncomingMessage(message);
  }

  /// Handle background messages (app is backgrounded)
  Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    debugPrint('🔔 Received background message: ${message.messageId}');

    // Navigate to conversation when notification is tapped
    await _navigateToConversation(message);
  }

  /// Process incoming message and show notification
  Future<void> _processIncomingMessage(RemoteMessage message) async {
    try {
      final data = message.data;
      final conversationId = data['conversation_id'] as String?;
      final messageId = data['message_id'] as String?;
      final senderId = data['sender_id'] as String?;
      final senderName = data['sender_name'] as String?;
      final messageContent = data['message_content'] as String?;
      final messageType = data['message_type'] as String?;

      if (conversationId == null || messageId == null || senderId == null) {
        debugPrint('⚠️ Invalid message data received');
        return;
      }

      // Don't show notifications for own messages
      final currentUserId = _supabase.auth.currentUser?.id;
      if (senderId == currentUserId) {
        debugPrint('🚫 Skipping notification for own message');
        return;
      }

      // Check if conversation notifications are enabled
      if (!await _preferencesService
          .areConversationNotificationsEnabled(conversationId)) {
        debugPrint(
            '🔕 Notifications disabled for conversation: $conversationId');
        return;
      }

      // CRITICAL FIX: Don't show notifications if user is currently viewing this conversation
      if (_currentActiveConversationId == conversationId) {
        debugPrint(
            '👁️ User is currently viewing conversation $conversationId, suppressing notification');
        return;
      }

      // Get sender's profile picture
      String? senderAvatarUrl;
      try {
        final profileResponse = await _supabase
            .from('profiles')
            .select('avatar_url')
            .eq('id', senderId)
            .maybeSingle();
        senderAvatarUrl = profileResponse?['avatar_url'] as String?;
      } catch (e) {
        debugPrint('⚠️ Could not fetch sender profile picture: $e');
      }

      // Group notifications by conversation
      await _addToNotificationGroup(conversationId, {
        'message_id': messageId,
        'sender_id': senderId,
        'sender_name': senderName ?? 'Unknown',
        'sender_avatar_url': senderAvatarUrl,
        'content': messageContent ?? 'New message',
        'type': messageType ?? 'text',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Show grouped notification
      await _showGroupedNotification(conversationId);
    } catch (e) {
      debugPrint('❌ Error processing incoming message: $e');
    }
  }

  /// Add message to notification group (persistent until conversation is opened)
  Future<void> _addToNotificationGroup(
      String conversationId, Map<String, dynamic> messageData) async {
    final messageId = messageData['message_id'] as String;

    // Initialize conversation tracking if needed
    if (!_groupedNotifications.containsKey(conversationId)) {
      _groupedNotifications[conversationId] = [];
      _seenMessageIds[conversationId] = <String>{};
    }

    // Check if we've already processed this message
    if (_seenMessageIds[conversationId]!.contains(messageId)) {
      debugPrint(
          '🔔 Message $messageId already processed for conversation $conversationId');
      return;
    }

    // Add message to group and mark as seen
    _groupedNotifications[conversationId]!.add(messageData);
    _seenMessageIds[conversationId]!.add(messageId);
    _lastNotificationTime[conversationId] = DateTime.now();

    debugPrint(
        '🔔 Added message to notification group: $conversationId (${_groupedNotifications[conversationId]!.length} total messages)');

    // Limit group size to prevent memory issues (keep most recent 20 messages)
    if (_groupedNotifications[conversationId]!.length > 20) {
      final removedMessage = _groupedNotifications[conversationId]!.removeAt(0);
      final removedMessageId = removedMessage['message_id'] as String;
      _seenMessageIds[conversationId]!.remove(removedMessageId);
    }
  }

  /// Show grouped notification for conversation
  Future<void> _showGroupedNotification(String conversationId) async {
    final messages = _groupedNotifications[conversationId];
    if (messages == null || messages.isEmpty) return;

    // WHATSAPP-STYLE FIX: Cancel existing notification FIRST to ensure replacement
    final notificationId = conversationId.hashCode.abs();
    try {
      await _localNotifications.cancel(notificationId);
      debugPrint(
          '🗑️ Cancelled existing notification ID: $notificationId for conversation: $conversationId');

      // Add a small delay to ensure cancellation completes before showing new notification
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      debugPrint('⚠️ Error during notification cancellation: $e');
    }

    final latestMessage = messages.last;
    final messageCount = messages.length;
    final senderName = latestMessage['sender_name'] as String;

    // Analyze message grouping
    final uniqueSenders =
        messages.map((msg) => msg['sender_name'] as String).toSet().toList();
    final isFromSameSender = uniqueSenders.length == 1;

    // Check privacy settings
    final showPreview = await _preferencesService.showMessagePreview();

    // Create notification title and determine style
    String title;
    String body;
    List<String>? messageLines; // For WhatsApp-style inbox display

    if (messageCount == 1) {
      // Single message - show sender name and content
      title = senderName;
      body = showPreview ? _getNotificationBody(latestMessage) : 'New message';
    } else if (isFromSameSender && showPreview) {
      // WHATSAPP-STYLE: Multiple messages from same sender - show all messages in inbox style
      title = senderName;
      messageLines = messages.map((msg) => _getNotificationBody(msg)).toList();

      // Limit to most recent 5 messages to prevent notification overflow
      if (messageLines.length > 5) {
        messageLines = messageLines.sublist(messageLines.length - 5);
        messageLines.insert(0, '... and ${messages.length - 5} more messages');
      }

      body = messageLines.join('\n'); // Fallback for summary
      debugPrint(
          '📱 WhatsApp-style notification: $title with ${messageLines.length} message lines');
    } else if (isFromSameSender) {
      // Same sender but privacy mode - just show count
      title = senderName;
      body = '$messageCount new messages';
    } else {
      // Messages from multiple senders
      title = 'PulseMeet';
      body = showPreview
          ? '$messageCount new messages from ${uniqueSenders.length} people'
          : '$messageCount new messages';
    }

    // Get sender's profile picture for notification
    final senderAvatarUrl = latestMessage['sender_avatar_url'] as String?;

    // Create notification with appropriate style using the SAME notification ID
    await _showLocalNotification(
      id: notificationId, // Use the same ID we cancelled with
      title: title,
      body: body,
      messageLines: messageLines, // Pass message lines for inbox style
      largeIconUrl: senderAvatarUrl,
      payload: jsonEncode({
        'type': 'message',
        'conversation_id': conversationId,
        'message_count': messageCount,
      }),
    );
  }

  /// Get notification body based on message type (optimized for WhatsApp-style display)
  String _getNotificationBody(Map<String, dynamic> messageData) {
    final type = messageData['type'] as String;
    final content = messageData['content'] as String;

    switch (type) {
      case 'text':
        // For WhatsApp-style notifications, use shorter truncation to fit multiple lines
        return content.length > 60 ? '${content.substring(0, 60)}...' : content;
      case 'image':
        return '📷 Photo';
      case 'video':
        return '🎥 Video';
      case 'audio':
        return '🎵 Voice message';
      case 'location':
        return '📍 Location';
      case 'file':
        return '📎 File';
      default:
        return 'New message';
    }
  }

  /// Load profile picture for notification
  Future<AndroidBitmap<Object>?> _loadProfilePictureForNotification(
      String imageUrl) async {
    try {
      debugPrint('🖼️ Downloading profile picture: $imageUrl');

      // Download the image
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        debugPrint('🖼️ Profile picture downloaded: ${bytes.length} bytes');

        // Convert to AndroidBitmap
        return ByteArrayAndroidBitmap(bytes);
      } else {
        debugPrint(
            '⚠️ Failed to download profile picture: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error loading profile picture for notification: $e');
      return null;
    }
  }

  /// Show local notification
  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? largeIconUrl,
    List<String>? messageLines, // For WhatsApp-style inbox notifications
  }) async {
    try {
      debugPrint('🔔 About to show local notification: $title - $body');

      // Get notification preferences
      final soundEnabled = await _preferencesService.isSoundEnabled();
      final vibrationEnabled = await _preferencesService.isVibrationEnabled();

      debugPrint(
          '🔔 Notification preferences: sound=$soundEnabled, vibration=$vibrationEnabled');

      // PROFILE PICTURE SUPPORT: Load user's profile picture for notification
      AndroidBitmap<Object>? largeIcon;
      try {
        if (largeIconUrl != null && largeIconUrl.isNotEmpty) {
          debugPrint(
              '🖼️ Loading profile picture for notification: $largeIconUrl');
          largeIcon = await _loadProfilePictureForNotification(largeIconUrl);
        }
      } catch (e) {
        debugPrint('⚠️ Failed to load profile picture for notification: $e');
      }

      // Fallback to default icon if profile picture loading failed
      largeIcon ??= const DrawableResourceAndroidBitmap('@mipmap/ic_launcher');

      // Determine notification style based on message content
      StyleInformation styleInformation;

      if (messageLines != null && messageLines.isNotEmpty) {
        // WHATSAPP-STYLE: Use InboxStyleInformation for multiple messages from same sender
        styleInformation = InboxStyleInformation(
          messageLines,
          contentTitle: title,
          summaryText: '${messageLines.length} messages',
          htmlFormatContent: false,
          htmlFormatContentTitle: false,
          htmlFormatSummaryText: false,
        );
        debugPrint(
            '📱 Using InboxStyleInformation with ${messageLines.length} message lines');
      } else {
        // Single message or fallback - use BigTextStyleInformation
        styleInformation = BigTextStyleInformation(
          body,
          contentTitle: title,
          htmlFormatBigText: false,
          htmlFormatContentTitle: false,
        );
        debugPrint('📱 Using BigTextStyleInformation for single message');
      }

      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        _notificationChannelId,
        _notificationChannelName,
        channelDescription: _notificationChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: vibrationEnabled,
        playSound: soundEnabled,
        icon: '@mipmap/ic_launcher',
        largeIcon: largeIcon, // Profile picture or fallback
        styleInformation:
            styleInformation, // WhatsApp-style or single message style
        autoCancel: true, // Auto-cancel when tapped
        ongoing: false, // Not persistent
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      debugPrint(
          '🔔 Calling _localNotifications.show() with id: $id, title: "$title"');
      debugPrint('🔔 Notification body: "$body"');
      if (messageLines != null) {
        debugPrint(
            '🔔 WhatsApp-style message lines (${messageLines.length}): ${messageLines.join(" | ")}');
        debugPrint('🔔 Using InboxStyleInformation for WhatsApp-style display');
      } else {
        debugPrint('🔔 Using BigTextStyleInformation for single message');
      }

      await _localNotifications.show(id, title, body, details,
          payload: payload);
      debugPrint(
          '✅ Local notification shown successfully with ID: $id, title: "$title"');
      debugPrint(
          '✅ Notification should replace any previous notification with same ID: $id');
    } catch (e) {
      debugPrint('❌ Error showing local notification: $e');
      debugPrint('❌ Notification details: id=$id, title=$title, body=$body');
      rethrow;
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('📱 Notification tapped: ${response.payload}');

    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);

        // Handle nested payload structure from push notifications
        String? conversationId;
        if (data['data'] != null && data['data']['conversation_id'] != null) {
          // Nested structure: {"type":"push_notification","data":{"conversation_id":"..."}}
          conversationId = data['data']['conversation_id'] as String?;
          debugPrint(
              '🧭 Found conversation ID in nested data: $conversationId');
        } else if (data['conversation_id'] != null) {
          // Direct structure: {"conversation_id":"..."}
          conversationId = data['conversation_id'] as String?;
          debugPrint(
              '🧭 Found conversation ID in direct data: $conversationId');
        }

        if (conversationId != null) {
          debugPrint('🧭 Navigating to conversation: $conversationId');
          _navigateToConversationById(conversationId);
        } else {
          debugPrint('❌ No conversation ID found in payload: $data');
        }
      } catch (e) {
        debugPrint('❌ Error parsing notification payload: $e');
      }
    }
  }

  /// Navigate to conversation
  Future<void> _navigateToConversation(RemoteMessage message) async {
    final conversationId = message.data['conversation_id'] as String?;
    if (conversationId != null) {
      _navigateToConversationById(conversationId);
    }
  }

  /// Navigate to conversation by ID
  void _navigateToConversationById(String conversationId) async {
    debugPrint('🧭 Navigating to conversation: $conversationId');

    try {
      // Import the main.dart file to access the navigator key
      final context = navigatorKey.currentContext;
      if (context == null) {
        debugPrint('❌ No navigator context available');
        return;
      }

      // Clear notifications for this conversation
      clearNotificationsForConversation(conversationId);

      // Get the conversation details from Supabase
      final conversationResponse = await _supabase
          .from('conversations')
          .select()
          .eq('id', conversationId)
          .maybeSingle();

      if (conversationResponse == null) {
        debugPrint('❌ Conversation not found: $conversationId');
        return;
      }

      // Create conversation object
      final conversation = Conversation.fromJson(conversationResponse);

      // Check if context is still valid before navigation
      final currentContext = navigatorKey.currentContext;
      if (currentContext == null) {
        debugPrint('❌ Navigator context no longer available');
        return;
      }

      // Navigate to the chat screen
      Navigator.of(currentContext).push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(conversation: conversation),
        ),
      );

      debugPrint('✅ Successfully navigated to conversation: $conversationId');
    } catch (e) {
      debugPrint('❌ Error navigating to conversation: $e');
    }
  }

  /// Set the currently active conversation (to suppress notifications)
  void setActiveConversation(String conversationId) {
    _currentActiveConversationId = conversationId;
    debugPrint('👁️ Set active conversation: $conversationId');

    // Also clear any existing notifications for this conversation
    clearNotificationsForConversation(conversationId);
  }

  /// Clear the currently active conversation (when user leaves chat)
  void clearActiveConversation() {
    final previousConversation = _currentActiveConversationId;
    _currentActiveConversationId = null;
    debugPrint('👁️ Cleared active conversation: $previousConversation');
  }

  /// Clear notifications for a conversation (when user opens the chat)
  Future<void> clearNotificationsForConversation(String conversationId) async {
    // Clear all tracking data for this conversation
    final messageCount = _groupedNotifications[conversationId]?.length ?? 0;
    _groupedNotifications.remove(conversationId);
    _seenMessageIds.remove(conversationId);
    _lastNotificationTime.remove(conversationId);

    // Cancel the actual notification using the same ID calculation as _showGroupedNotification
    final notificationId = conversationId.hashCode.abs();
    await _localNotifications.cancel(notificationId);

    debugPrint(
        '🗑️ Cleared $messageCount grouped notifications for conversation: $conversationId (ID: $notificationId)');
  }

  /// Get FCM token
  String? get fcmToken => _fcmToken;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Test method to directly show a local notification (for debugging)
  Future<void> testLocalNotification() async {
    debugPrint('🧪 Testing local notification directly...');
    try {
      // Use a 32-bit safe notification ID
      final testNotificationId =
          DateTime.now().millisecondsSinceEpoch % 2147483647;
      await _showLocalNotification(
        id: testNotificationId,
        title: 'Test Notification',
        body: 'This is a direct test of the local notification system!',
        payload: jsonEncode({
          'type': 'test',
          'data': {'test': true},
        }),
      );
      debugPrint('✅ Test local notification completed');
    } catch (e) {
      debugPrint('❌ Test local notification failed: $e');
    }
  }

  /// Clear all notifications (for testing)
  Future<void> clearAllNotifications() async {
    try {
      await _localNotifications.cancelAll();
      _groupedNotifications.clear();
      _seenMessageIds.clear();
      _lastNotificationTime.clear();
      debugPrint('🗑️ Cleared all notifications and tracking data');
    } catch (e) {
      debugPrint('❌ Error clearing all notifications: $e');
    }
  }

  /// Test WhatsApp-style notification with multiple messages from same sender
  Future<void> testWhatsAppStyleNotification() async {
    debugPrint('🧪 Testing WhatsApp-style notification...');
    try {
      const testConversationId = 'test_whatsapp_conversation';

      // CRITICAL FIX: Clear ALL notifications first to ensure clean test
      await clearAllNotifications();
      debugPrint('🧪 Cleared all notifications for clean test');

      // Simulate multiple messages from the same sender using the real flow
      final testMessages = [
        {
          'message_id': 'msg1',
          'sender_id': 'user123',
          'sender_name': 'Alice',
          'sender_avatar_url': null,
          'content': 'Hey there!',
          'type': 'text',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        {
          'message_id': 'msg2',
          'sender_id': 'user123',
          'sender_name': 'Alice',
          'sender_avatar_url': null,
          'content': 'Are you coming to the meeting?',
          'type': 'text',
          'timestamp': DateTime.now().millisecondsSinceEpoch + 1000,
        },
        {
          'message_id': 'msg3',
          'sender_id': 'user123',
          'sender_name': 'Alice',
          'sender_avatar_url': null,
          'content': 'Let me know ASAP please',
          'type': 'text',
          'timestamp': DateTime.now().millisecondsSinceEpoch + 2000,
        },
      ];

      // CRITICAL FIX: Use the real notification flow to ensure proper replacement
      for (int i = 0; i < testMessages.length; i++) {
        final messageData = testMessages[i];
        debugPrint(
            '🧪 Processing test message ${i + 1}/${testMessages.length}: ${messageData['content']}');

        await _addToNotificationGroup(testConversationId, messageData);
        await _showGroupedNotification(testConversationId);

        debugPrint(
            '🧪 Completed test message ${i + 1}, waiting before next...');
        // Add a small delay between messages to simulate real-world timing
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      debugPrint(
          '✅ WhatsApp-style test notification completed with ${testMessages.length} messages');
    } catch (e) {
      debugPrint('❌ WhatsApp-style test notification failed: $e');
    }
  }

  /// Dispose service
  void dispose() {
    _groupedNotifications.clear();
    debugPrint('🧹 Firebase Messaging Service disposed');
  }
}

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🔔 Background message received: ${message.messageId}');

  // Handle background message processing here
  // This runs when the app is completely terminated
}
