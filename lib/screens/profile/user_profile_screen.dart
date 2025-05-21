import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as provider_pkg;
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'package:pulsemeet/models/connection.dart';
import 'package:pulsemeet/models/rating.dart';
import 'package:pulsemeet/services/supabase_service.dart';
import 'package:pulsemeet/services/connection_service.dart';
import 'package:pulsemeet/services/rating_service.dart';
import 'package:pulsemeet/screens/chat/direct_message_screen.dart';
import 'package:pulsemeet/screens/profile/ratings_screen.dart';
import 'package:pulsemeet/widgets/profile/profile_header.dart';
import 'package:pulsemeet/widgets/profile/profile_info_section.dart';
import 'package:pulsemeet/widgets/profile/profile_rating_section.dart';
import 'package:pulsemeet/widgets/profile/profile_stats_section.dart';
import 'package:pulsemeet/widgets/pulse_card.dart';
import 'package:pulsemeet/widgets/rating/rating_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Screen for viewing another user's profile
class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _connectionService = ConnectionService();
  final _ratingService = RatingService();

  Profile? _profile;
  List<Pulse> _userPulses = [];
  ConnectionStatus? _connectionStatus;
  bool _isLoading = true;
  bool _isLoadingConnection = true;
  bool _isProcessingConnection = false;
  String? _errorMessage;
  bool _canRateUser = false;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _fetchUserPulses();
    _checkConnectionStatus();
    _checkIfCanRateUser();
  }

  /// Fetch user profile
  Future<void> _fetchProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabaseService =
          provider_pkg.Provider.of<SupabaseService>(context, listen: false);

      final profile = await supabaseService.getProfile(widget.userId);

      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error fetching profile: ${e.toString()}';
      });
    }
  }

  /// Fetch pulses created by this user
  Future<void> _fetchUserPulses() async {
    try {
      final supabaseService =
          provider_pkg.Provider.of<SupabaseService>(context, listen: false);

      final pulses = await supabaseService.getPulsesByCreator(widget.userId);

      setState(() {
        _userPulses = pulses;
      });
    } catch (e) {
      debugPrint('Error fetching user pulses: $e');
    }
  }

  /// Check connection status with this user
  Future<void> _checkConnectionStatus() async {
    setState(() {
      _isLoadingConnection = true;
    });

    try {
      final status =
          await _connectionService.checkConnectionStatus(widget.userId);

      setState(() {
        _connectionStatus = status;
        _isLoadingConnection = false;
      });
    } catch (e) {
      debugPrint('Error checking connection status: $e');
      setState(() {
        _isLoadingConnection = false;
      });
    }
  }

  /// Send a connection request
  Future<void> _sendConnectionRequest() async {
    if (_isProcessingConnection) return;

    setState(() {
      _isProcessingConnection = true;
    });

    try {
      await _connectionService.sendConnectionRequest(widget.userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Connection request sent to ${_profile?.displayName ?? _profile?.username ?? 'User'}'),
          ),
        );

        setState(() {
          _connectionStatus = ConnectionStatus.pending;
          _isProcessingConnection = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending connection request: ${e.toString()}'),
          ),
        );

        setState(() {
          _isProcessingConnection = false;
        });
      }
    }
  }

  /// Accept a connection request
  Future<void> _acceptConnectionRequest() async {
    if (_isProcessingConnection) return;

    setState(() {
      _isProcessingConnection = true;
    });

    try {
      // We need to find the connection ID first
      final connections = await _connectionService.fetchPendingRequests();
      final connection = connections.firstWhere(
        (c) => c.requesterId == widget.userId,
        orElse: () => throw Exception('Connection request not found'),
      );

      await _connectionService.acceptConnectionRequest(connection.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Connection request from ${_profile?.displayName ?? _profile?.username ?? 'User'} accepted'),
          ),
        );

        setState(() {
          _connectionStatus = ConnectionStatus.accepted;
          _isProcessingConnection = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Error accepting connection request: ${e.toString()}'),
          ),
        );

        setState(() {
          _isProcessingConnection = false;
        });
      }
    }
  }

  /// Check if the current user can rate this user
  Future<void> _checkIfCanRateUser() async {
    try {
      // Get the most recent pulse where both users participated
      final supabaseService =
          provider_pkg.Provider.of<SupabaseService>(context, listen: false);

      // Get pulses where the current user participated
      final pulses = await supabaseService.getParticipatedPulses();

      // Find pulses created by the viewed user
      for (final pulse in pulses) {
        if (pulse.creatorId == widget.userId) {
          // Check if the user can rate for this pulse
          final canRate =
              await _ratingService.canRateUser(widget.userId, pulse.id);
          if (canRate) {
            setState(() {
              _canRateUser = true;
            });
            return;
          }
        }
      }

      setState(() {
        _canRateUser = false;
      });
    } catch (e) {
      debugPrint('Error checking if user can be rated: $e');
      setState(() {
        _canRateUser = false;
      });
    }
  }

  /// Show rating dialog
  Future<void> _showRatingDialog() async {
    if (_profile == null) return;

    // Get the most recent pulse where both users participated
    final supabaseService =
        provider_pkg.Provider.of<SupabaseService>(context, listen: false);

    // Get pulses where the current user participated
    final pulses = await supabaseService.getParticipatedPulses();

    // Find the most recent pulse created by the viewed user
    Pulse? mostRecentPulse;
    for (final pulse in pulses) {
      if (pulse.creatorId == widget.userId) {
        if (mostRecentPulse == null ||
            pulse.startTime.isAfter(mostRecentPulse.startTime)) {
          mostRecentPulse = pulse;
        }
      }
    }

    if (mostRecentPulse == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No shared pulses found to rate this user'),
          ),
        );
      }
      return;
    }

    if (mounted) {
      final result = await showRatingDialog(
        context,
        userToRate: _profile!,
        pulseId: mostRecentPulse.id,
        onRatingSubmitted: () {
          // Refresh profile to get updated rating
          _fetchProfile();
        },
      );

      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rating submitted successfully'),
          ),
        );
      }
    }
  }

  /// Navigate to ratings screen
  Future<void> _navigateToRatingsScreen() async {
    if (_profile == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RatingsScreen(profile: _profile!),
      ),
    );
  }

  /// Remove connection
  Future<void> _removeConnection() async {
    if (_isProcessingConnection) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Connection'),
        content: Text(
            'Are you sure you want to remove ${_profile?.displayName ?? _profile?.username ?? 'User'} from your connections?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessingConnection = true;
    });

    try {
      // We need to find the connection ID first
      final connections = await _connectionService.fetchConnections();
      final connection = connections.firstWhere(
        (c) => c.isWithUser(widget.userId),
        orElse: () => throw Exception('Connection not found'),
      );

      await _connectionService.removeConnection(connection.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${_profile?.displayName ?? _profile?.username ?? 'User'} removed from your connections'),
          ),
        );

        setState(() {
          _connectionStatus = null;
          _isProcessingConnection = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing connection: ${e.toString()}'),
          ),
        );

        setState(() {
          _isProcessingConnection = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_profile?.displayName ?? 'User Profile'),
        actions: [
          if (_profile != null &&
              _connectionStatus == ConnectionStatus.accepted)
            IconButton(
              icon: const Icon(Icons.message_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DirectMessageScreen(
                      otherUserId: widget.userId,
                      otherUserProfile: _profile,
                    ),
                  ),
                );
              },
              tooltip: 'Message',
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

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchProfile,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_profile == null) {
      return const Center(
        child: Text('User not found'),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchProfile();
        await _fetchUserPulses();
        await _checkConnectionStatus();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Profile header with avatar and name
            ProfileHeader(profile: _profile!),

            const SizedBox(height: 16),

            // Connection button
            if (widget.userId != Supabase.instance.client.auth.currentUser?.id)
              Column(
                children: [
                  _buildConnectionButton(),
                  if (_canRateUser)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: OutlinedButton.icon(
                        onPressed: _showRatingDialog,
                        icon: const Icon(Icons.star_outline),
                        label: const Text('Rate User'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 16),

            // Profile stats
            ProfileStatsSection(
              pulsesCreated: _userPulses.length,
              pulsesJoined: 0, // We don't have this data
              connections: 0, // We don't have this data
              onPulsesCreatedTap: () {
                // Already showing pulses below
              },
              onPulsesJoinedTap: () {
                // Not implemented
              },
              onConnectionsTap: () {
                // Not implemented
              },
            ),

            const SizedBox(height: 16),

            // Profile info
            ProfileInfoSection(
              profile: _profile!,
              onEditTap: null, // Can't edit another user's profile
            ),

            const SizedBox(height: 16),

            // Rating section
            ProfileRatingSection(
              profile: _profile!,
              showDetailedBreakdown: true,
              showRatings: true,
              maxRatingsToShow: 2,
              onViewAllTap: _navigateToRatingsScreen,
            ),

            const SizedBox(height: 24),

            // Pulses created by this user
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pulses Created',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_userPulses.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text('No pulses created yet'),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _userPulses.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: PulseCard(
                            pulse: _userPulses[index],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionButton() {
    if (_isLoadingConnection) {
      return const SizedBox(
        height: 36,
        width: 36,
        child: CircularProgressIndicator(),
      );
    }

    // Current user's profile
    if (widget.userId == Supabase.instance.client.auth.currentUser?.id) {
      return const SizedBox.shrink();
    }

    // No connection
    if (_connectionStatus == null) {
      return ElevatedButton.icon(
        onPressed: _isProcessingConnection ? null : _sendConnectionRequest,
        icon: const Icon(Icons.person_add),
        label: const Text('Connect'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      );
    }

    // Pending connection (sent by current user)
    if (_connectionStatus == ConnectionStatus.pending) {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;

      // If we sent the request
      if (currentUserId != widget.userId) {
        return OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.pending_outlined),
          label: const Text('Request Sent'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        );
      }
      // If they sent the request
      else {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed:
                  _isProcessingConnection ? null : _acceptConnectionRequest,
              icon: const Icon(Icons.check),
              label: const Text('Accept'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                backgroundColor: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _isProcessingConnection
                  ? null
                  : () {}, // TODO: Implement decline
              icon: const Icon(Icons.close),
              label: const Text('Decline'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                foregroundColor: Colors.red,
              ),
            ),
          ],
        );
      }
    }

    // Connected
    if (_connectionStatus == ConnectionStatus.accepted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DirectMessageScreen(
                    otherUserId: widget.userId,
                    otherUserProfile: _profile,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.message_outlined),
            label: const Text('Message'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _isProcessingConnection ? null : _removeConnection,
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Remove'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              foregroundColor: Colors.red,
            ),
          ),
        ],
      );
    }

    // Declined or blocked
    return OutlinedButton.icon(
      onPressed: _isProcessingConnection ? null : _sendConnectionRequest,
      icon: const Icon(Icons.refresh),
      label: const Text('Send New Request'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );
  }
}
