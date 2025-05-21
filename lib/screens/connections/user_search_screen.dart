import 'package:flutter/material.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/connection_service.dart';
import 'package:pulsemeet/screens/profile/user_profile_screen.dart';
import 'package:pulsemeet/widgets/profile/profile_list_item.dart';

/// Screen for searching users to connect with
class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _searchController = TextEditingController();
  final _connectionService = ConnectionService();
  
  bool _isLoading = false;
  List<Profile> _searchResults = [];
  String _errorMessage = '';
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  /// Search for users
  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _errorMessage = '';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    
    try {
      final results = await _connectionService.searchUsers(query);
      
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
          
          if (results.isEmpty) {
            _errorMessage = 'No users found matching "$query"';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error searching for users: ${e.toString()}';
        });
      }
    }
  }
  
  /// Send a connection request
  Future<void> _sendConnectionRequest(Profile profile) async {
    try {
      await _connectionService.sendConnectionRequest(profile.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection request sent to ${profile.displayName ?? profile.username}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending connection request: ${e.toString()}'),
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
        title: const Text('Find People'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by username or display name',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                            _errorMessage = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchUsers(),
              onChanged: (value) {
                if (value.isEmpty) {
                  setState(() {
                    _searchResults = [];
                    _errorMessage = '';
                  });
                }
              },
            ),
          ),
          
          // Search button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _searchUsers,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                child: const Text('Search'),
              ),
            ),
          ),
          
          const SizedBox(height: 16.0),
          
          // Results
          Expanded(
            child: _buildResults(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildResults() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Text(
          _errorMessage,
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      );
    }
    
    if (_searchResults.isEmpty) {
      return const Center(
        child: Text(
          'Search for users by username or display name',
          textAlign: TextAlign.center,
        ),
      );
    }
    
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final profile = _searchResults[index];
        return ProfileListItem(
          profile: profile,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfileScreen(userId: profile.id),
              ),
            );
          },
          trailing: IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _sendConnectionRequest(profile),
            tooltip: 'Send connection request',
          ),
        );
      },
    );
  }
}
