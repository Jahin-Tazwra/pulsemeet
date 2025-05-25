import 'package:flutter/material.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/connection_service.dart';
import 'package:pulsemeet/screens/profile/user_profile_screen.dart';
import 'package:pulsemeet/widgets/profile/profile_list_item.dart';
import 'package:pulsemeet/widgets/common/loading_indicator.dart';
import 'package:pulsemeet/widgets/common/error_widget.dart';

/// Flexible user search screen that can be used for different purposes
class UserSearchScreen extends StatefulWidget {
  final String? title;
  final Function(Profile)? onUserSelected;
  final bool showConnectionButton;
  final String? searchHint;

  const UserSearchScreen({
    super.key,
    this.title,
    this.onUserSelected,
    this.showConnectionButton = false,
    this.searchHint,
  });

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
  
  /// Send connection request to user
  Future<void> _sendConnectionRequest(Profile profile) async {
    try {
      await _connectionService.sendConnectionRequest(profile.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection request sent to ${profile.displayName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send connection request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Handle user selection
  void _handleUserSelection(Profile profile) {
    if (widget.onUserSelected != null) {
      widget.onUserSelected!(profile);
    } else {
      // Default behavior: navigate to user profile
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(userId: profile.id),
        ),
      );
    }
  }

  /// Clear search
  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _errorMessage = '';
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        title: Text(
          widget.title ?? 'Search Users',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: widget.searchHint ?? 'Search by username or display name',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                filled: true,
                fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
              ),
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchUsers(),
              onChanged: (value) {
                if (value.isEmpty) {
                  _clearSearch();
                }
                setState(() {}); // Update UI for suffix icon
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
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
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
      return const Center(child: LoadingIndicator());
    }
    
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: CustomErrorWidget(
          message: _errorMessage,
          onRetry: _searchUsers,
        ),
      );
    }
    
    if (_searchResults.isEmpty && _searchController.text.isNotEmpty) {
      return _buildEmptyState();
    }
    
    if (_searchResults.isEmpty) {
      return _buildInitialState();
    }
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final profile = _searchResults[index];
        return ProfileListItem(
          profile: profile,
          onTap: () => _handleUserSelection(profile),
          trailing: widget.showConnectionButton
              ? IconButton(
                  icon: const Icon(Icons.person_add),
                  onPressed: () => _sendConnectionRequest(profile),
                  tooltip: 'Send connection request',
                )
              : widget.onUserSelected != null
                  ? const Icon(Icons.arrow_forward_ios, size: 16)
                  : null,
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No users found',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching with different keywords',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.grey[500] : Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInitialState() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Search for users',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter a username or display name to find users',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.grey[500] : Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
