import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pulsemeet/models/connection.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/notification_service.dart';

/// Service for managing user connections
class ConnectionService {
  // Singleton instance
  static final ConnectionService _instance = ConnectionService._internal();

  factory ConnectionService() => _instance;

  ConnectionService._internal() {
    _initStreams();
  }

  // Supabase client
  final _supabase = Supabase.instance.client;

  // Notification service
  final _notificationService = NotificationService();

  // Stream controllers
  final _connectionsController = StreamController<List<Connection>>.broadcast();
  final _pendingRequestsController =
      StreamController<List<Connection>>.broadcast();
  final _outgoingRequestsController =
      StreamController<List<Connection>>.broadcast();
  final _connectionStatusController = StreamController<Connection>.broadcast();

  // Cached data
  List<Connection> _connections = [];
  List<Connection> _pendingRequests = [];
  List<Connection> _outgoingRequests = [];

  // Subscription and channel
  StreamSubscription? _connectionSubscription;
  RealtimeChannel? _connectionChannel;

  /// Stream of connections
  Stream<List<Connection>> get connectionsStream =>
      _connectionsController.stream;

  /// Stream of pending connection requests
  Stream<List<Connection>> get pendingRequestsStream =>
      _pendingRequestsController.stream;

  /// Stream of outgoing connection requests
  Stream<List<Connection>> get outgoingRequestsStream =>
      _outgoingRequestsController.stream;

  /// Stream of connection status changes
  Stream<Connection> get connectionStatusStream =>
      _connectionStatusController.stream;

  /// Get the current list of connections
  List<Connection> get connections => _connections;

  /// Get the current list of pending requests
  List<Connection> get pendingRequests => _pendingRequests;

  /// Get the current list of outgoing requests
  List<Connection> get outgoingRequests => _outgoingRequests;

  /// Get the current user ID
  String? get currentUserId => _supabase.auth.currentUser?.id;

  /// Initialize streams
  void _initStreams() {
    // Add initial empty data
    _connectionsController.add([]);
    _pendingRequestsController.add([]);
    _outgoingRequestsController.add([]);

    // Subscribe to connection changes
    _subscribeToConnections();
  }

  /// Subscribe to connection changes
  void _subscribeToConnections() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Cancel existing subscription
    _connectionSubscription?.cancel();

    // Subscribe to connections table for changes
    final channel = _supabase.channel('public:connections');

    channel.on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(
        event: '*',
        schema: 'public',
        table: 'connections',
        filter: 'requester_id=eq.$userId',
      ),
      (payload, [ref]) {
        debugPrint(
            'Connection change detected for requester: ${payload['eventType']}');
        // Refresh connections on any change
        fetchConnections();
        fetchPendingRequests();
        fetchOutgoingRequests();

        // If this is an update, notify about the status change
        if (payload['eventType'] == 'UPDATE' && payload['new'] != null) {
          final connection = Connection.fromJson(payload['new']);
          _connectionStatusController.add(connection);
        }
      },
    );

    // Also listen for changes where current user is the receiver
    channel.on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(
        event: '*',
        schema: 'public',
        table: 'connections',
        filter: 'receiver_id=eq.$userId',
      ),
      (payload, [ref]) {
        debugPrint(
            'Connection change detected for receiver: ${payload['eventType']}');
        // Refresh connections on any change
        fetchConnections();
        fetchPendingRequests();
        fetchOutgoingRequests();

        // If this is an update, notify about the status change
        if (payload['eventType'] == 'UPDATE' && payload['new'] != null) {
          final connection = Connection.fromJson(payload['new']);
          _connectionStatusController.add(connection);
        }
      },
    );

    channel.subscribe((status, [error]) {
      if (error != null) {
        debugPrint('Error subscribing to connections: $error');
      } else {
        debugPrint('Subscribed to connections: $status');
      }
    });

    // Store the channel for later cancellation
    _connectionChannel = channel;
  }

  /// Check if a connection exists with a user
  Future<ConnectionStatus?> checkConnectionStatus(String otherUserId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final response = await _supabase
          .from('connections')
          .select()
          .or('requester_id.eq.$userId,receiver_id.eq.$userId')
          .or('requester_id.eq.$otherUserId,receiver_id.eq.$otherUserId')
          .limit(1);

      if (response.isNotEmpty) {
        final connection = Connection.fromJson(response[0]);
        return connection.status;
      }

      return null;
    } catch (e) {
      debugPrint('Error checking connection status: $e');
      return null;
    }
  }

  /// Send a connection request
  Future<Connection?> sendConnectionRequest(String receiverId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      // Check if a connection already exists
      final existingStatus = await checkConnectionStatus(receiverId);
      if (existingStatus != null) {
        throw Exception('A connection already exists with this user');
      }

      // Create the connection request
      final response = await _supabase
          .from('connections')
          .insert({
            'requester_id': userId,
            'receiver_id': receiverId,
            'status': 'pending',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final connection = Connection.fromJson(response);

      // Refresh connections
      await fetchPendingRequests();
      await fetchOutgoingRequests();

      // Send notification to receiver
      _notificationService.sendConnectionRequestNotification(receiverId);

      return connection;
    } catch (e) {
      debugPrint('Error sending connection request: $e');
      rethrow;
    }
  }

  /// Accept a connection request
  Future<Connection?> acceptConnectionRequest(String connectionId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      // Update the connection status
      final response = await _supabase
          .from('connections')
          .update({
            'status': 'accepted',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', connectionId)
          .eq('receiver_id', userId) // Ensure the current user is the receiver
          .select()
          .single();

      final connection = Connection.fromJson(response);

      // Refresh connections
      await fetchConnections();
      await fetchPendingRequests();

      // Send notification to requester
      _notificationService
          .sendConnectionAcceptedNotification(connection.requesterId);

      return connection;
    } catch (e) {
      debugPrint('Error accepting connection request: $e');
      rethrow;
    }
  }

  /// Decline a connection request
  Future<Connection?> declineConnectionRequest(String connectionId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      // Update the connection status
      final response = await _supabase
          .from('connections')
          .update({
            'status': 'declined',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', connectionId)
          .eq('receiver_id', userId) // Ensure the current user is the receiver
          .select()
          .single();

      final connection = Connection.fromJson(response);

      // Refresh connections
      await fetchPendingRequests();

      return connection;
    } catch (e) {
      debugPrint('Error declining connection request: $e');
      rethrow;
    }
  }

  /// Cancel an outgoing connection request
  Future<void> cancelConnectionRequest(String connectionId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Delete the connection request
      await _supabase
          .from('connections')
          .delete()
          .eq('id', connectionId)
          .eq('requester_id',
              userId) // Ensure the current user is the requester
          .eq('status', 'pending'); // Only allow canceling pending requests

      // Refresh connections
      await fetchOutgoingRequests();
    } catch (e) {
      debugPrint('Error canceling connection request: $e');
      rethrow;
    }
  }

  /// Remove a connection
  Future<void> removeConnection(String connectionId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Delete the connection
      await _supabase.from('connections').delete().eq('id', connectionId).or(
          'requester_id.eq.$userId,receiver_id.eq.$userId'); // Ensure the current user is involved

      // Refresh connections
      await fetchConnections();
    } catch (e) {
      debugPrint('Error removing connection: $e');
      rethrow;
    }
  }

  /// Block a user
  Future<Connection?> blockUser(String otherUserId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      // Check if a connection already exists
      final existingStatus = await checkConnectionStatus(otherUserId);

      if (existingStatus != null) {
        // Update existing connection to blocked
        final response = await _supabase
            .from('connections')
            .update({
              'status': 'blocked',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .or('and(requester_id.eq.$userId,receiver_id.eq.$otherUserId),and(requester_id.eq.$otherUserId,receiver_id.eq.$userId)')
            .select()
            .single();

        final connection = Connection.fromJson(response);

        // Refresh connections
        await fetchConnections();
        await fetchPendingRequests();

        return connection;
      } else {
        // Create new blocked connection
        final response = await _supabase
            .from('connections')
            .insert({
              'requester_id': userId,
              'receiver_id': otherUserId,
              'status': 'blocked',
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .select()
            .single();

        final connection = Connection.fromJson(response);

        // Refresh connections
        await fetchConnections();

        return connection;
      }
    } catch (e) {
      debugPrint('Error blocking user: $e');
      rethrow;
    }
  }

  /// Fetch all accepted connections
  Future<List<Connection>> fetchConnections() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _supabase
          .from('connections')
          .select('''
          *,
          requester_profile:profiles!fk_connections_requester_profile(id, username, display_name, avatar_url, created_at, updated_at, last_seen_at),
          receiver_profile:profiles!fk_connections_receiver_profile(id, username, display_name, avatar_url, created_at, updated_at, last_seen_at)
        ''')
          .or('requester_id.eq.$userId,receiver_id.eq.$userId')
          .eq('status', 'accepted');

      _connections = response
          .map<Connection>((json) => Connection.fromJson(json))
          .toList();
      _connectionsController.add(_connections);

      return _connections;
    } catch (e) {
      debugPrint('Error fetching connections: $e');
      return [];
    }
  }

  /// Fetch pending connection requests
  Future<List<Connection>> fetchPendingRequests() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _supabase.from('connections').select('''
          *,
          requester_profile:profiles!fk_connections_requester_profile(id, username, display_name, avatar_url, created_at, updated_at, last_seen_at),
          receiver_profile:profiles!fk_connections_receiver_profile(id, username, display_name, avatar_url, created_at, updated_at, last_seen_at)
        ''').eq('receiver_id', userId).eq('status', 'pending');

      _pendingRequests = response
          .map<Connection>((json) => Connection.fromJson(json))
          .toList();
      _pendingRequestsController.add(_pendingRequests);

      return _pendingRequests;
    } catch (e) {
      debugPrint('Error fetching pending requests: $e');
      return [];
    }
  }

  /// Fetch outgoing connection requests
  Future<List<Connection>> fetchOutgoingRequests() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _supabase.from('connections').select('''
          *,
          requester_profile:profiles!fk_connections_requester_profile(id, username, display_name, avatar_url, created_at, updated_at, last_seen_at),
          receiver_profile:profiles!fk_connections_receiver_profile(id, username, display_name, avatar_url, created_at, updated_at, last_seen_at)
        ''').eq('requester_id', userId).eq('status', 'pending');

      _outgoingRequests = response
          .map<Connection>((json) => Connection.fromJson(json))
          .toList();
      _outgoingRequestsController.add(_outgoingRequests);

      return _outgoingRequests;
    } catch (e) {
      debugPrint('Error fetching outgoing requests: $e');
      return [];
    }
  }

  /// Search for users by username or display name
  Future<List<Profile>> searchUsers(String query) async {
    if (query.isEmpty) return [];

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .or('username.ilike.%$query%,display_name.ilike.%$query%')
          .neq('id', userId) // Exclude current user
          .limit(20);

      return response.map<Profile>((json) => Profile.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error searching users: $e');
      return [];
    }
  }

  /// Get connection count
  Future<int> getConnectionCount() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return 0;

    try {
      final response = await _supabase
          .from('connections')
          .select('id', const FetchOptions(count: CountOption.exact))
          .or('requester_id.eq.$userId,receiver_id.eq.$userId')
          .eq('status', 'accepted');

      return response.count ?? 0;
    } catch (e) {
      debugPrint('Error getting connection count: $e');
      return 0;
    }
  }

  /// Dispose resources
  void dispose() {
    _connectionsController.close();
    _pendingRequestsController.close();
    _outgoingRequestsController.close();
    _connectionStatusController.close();
    _connectionChannel?.unsubscribe();
  }
}
