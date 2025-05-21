import 'package:flutter/material.dart';
import 'package:pulsemeet/models/connection.dart';
import 'package:pulsemeet/services/connection_service.dart';
import 'package:pulsemeet/screens/profile/user_profile_screen.dart';
import 'package:pulsemeet/widgets/profile/profile_list_item.dart';

/// Screen for viewing and managing connection requests
class ConnectionRequestsScreen extends StatefulWidget {
  const ConnectionRequestsScreen({super.key});

  @override
  State<ConnectionRequestsScreen> createState() => _ConnectionRequestsScreenState();
}

class _ConnectionRequestsScreenState extends State<ConnectionRequestsScreen> {
  final _connectionService = ConnectionService();
  
  bool _isLoading = true;
  List<Connection> _pendingRequests = [];
  String _errorMessage = '';
  
  @override
  void initState() {
    super.initState();
    _fetchPendingRequests();
  }
  
  /// Fetch pending connection requests
  Future<void> _fetchPendingRequests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    
    try {
      final requests = await _connectionService.fetchPendingRequests();
      
      if (mounted) {
        setState(() {
          _pendingRequests = requests;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error fetching connection requests: ${e.toString()}';
        });
      }
    }
  }
  
  /// Accept a connection request
  Future<void> _acceptRequest(Connection request) async {
    try {
      await _connectionService.acceptConnectionRequest(request.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection request from ${request.requesterProfile?.displayName ?? request.requesterProfile?.username ?? 'User'} accepted'),
            duration: const Duration(seconds: 2),
          ),
        );
        
        // Refresh the list
        _fetchPendingRequests();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accepting connection request: ${e.toString()}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  /// Decline a connection request
  Future<void> _declineRequest(Connection request) async {
    try {
      await _connectionService.declineConnectionRequest(request.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection request from ${request.requesterProfile?.displayName ?? request.requesterProfile?.username ?? 'User'} declined'),
            duration: const Duration(seconds: 2),
          ),
        );
        
        // Refresh the list
        _fetchPendingRequests();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error declining connection request: ${e.toString()}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPendingRequests,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
  
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: _fetchPendingRequests,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    
    if (_pendingRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.people_outline,
              size: 64.0,
              color: Colors.grey,
            ),
            const SizedBox(height: 16.0),
            const Text(
              'No pending connection requests',
              style: TextStyle(fontSize: 18.0),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            const Text(
              'When someone sends you a connection request, it will appear here',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: _fetchPendingRequests,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _fetchPendingRequests,
      child: ListView.builder(
        itemCount: _pendingRequests.length,
        itemBuilder: (context, index) {
          final request = _pendingRequests[index];
          final requester = request.requesterProfile;
          
          if (requester == null) {
            return const SizedBox.shrink();
          }
          
          return ProfileListItem(
            profile: requester,
            subtitle: Text('Sent a connection request'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfileScreen(userId: requester.id),
                ),
              );
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () => _acceptRequest(request),
                  tooltip: 'Accept',
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _declineRequest(request),
                  tooltip: 'Decline',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
