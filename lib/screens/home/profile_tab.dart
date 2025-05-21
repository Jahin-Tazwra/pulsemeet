import 'package:flutter/material.dart' hide ThemeMode;
import 'package:provider/provider.dart';
import 'package:pulsemeet/services/supabase_service.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/screens/profile/edit_profile_screen.dart';
import 'package:pulsemeet/screens/profile/ratings_screen.dart';
import 'package:pulsemeet/widgets/profile/profile_header.dart';
import 'package:pulsemeet/widgets/profile/profile_info_section.dart';
import 'package:pulsemeet/widgets/profile/profile_rating_section.dart';
import 'package:pulsemeet/widgets/profile/profile_stats_section.dart';
import 'package:pulsemeet/widgets/profile/settings_section.dart';
import 'package:pulsemeet/providers/theme_provider.dart';

/// Tab showing user profile
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Profile? _profile;
  bool _isLoading = true;
  String? _errorMessage;
  int _pulsesCreated = 0;
  int _pulsesJoined = 0;
  int _connections = 0;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _fetchStats();
  }

  /// Fetch user profile
  Future<void> _fetchProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabaseService =
          Provider.of<SupabaseService>(context, listen: false);
      final userId = supabaseService.currentUserId;

      if (userId == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'User not authenticated';
        });
        return;
      }

      final profile = await supabaseService.getProfile(userId);

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

  /// Fetch user stats
  Future<void> _fetchStats() async {
    try {
      final supabaseService =
          Provider.of<SupabaseService>(context, listen: false);
      final userId = supabaseService.currentUserId;

      if (userId == null) {
        return;
      }

      // In a real implementation, these would be fetched from the database
      // For now, we'll use dummy data
      setState(() {
        _pulsesCreated = 5;
        _pulsesJoined = 12;
        _connections = 24;
      });
    } catch (e) {
      debugPrint('Error fetching stats: $e');
    }
  }

  /// Show sign out confirmation dialog
  Future<void> _confirmSignOut() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _signOut();
    }
  }

  /// Sign out the user
  Future<void> _signOut() async {
    try {
      final supabaseService =
          Provider.of<SupabaseService>(context, listen: false);
      await supabaseService.signOut();
      // Auth state change will automatically navigate to auth screen
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: ${e.toString()}')),
        );
      }
    }
  }

  /// Navigate to edit profile screen
  Future<void> _navigateToEditProfile() async {
    if (_profile == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(profile: _profile!),
      ),
    );

    // Refresh profile after editing
    _fetchProfile();
  }

  /// Navigate to notification settings screen
  Future<void> _navigateToNotificationSettings() async {
    if (_profile == null) return;

    // This would navigate to the notification settings screen
    // For now, we'll just show a snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification settings coming soon')),
      );
    }
  }

  /// Navigate to privacy settings screen
  Future<void> _navigateToPrivacySettings() async {
    if (_profile == null) return;

    // This would navigate to the privacy settings screen
    // For now, we'll just show a snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Privacy settings coming soon')),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _confirmSignOut,
            tooltip: 'Sign Out',
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
            FilledButton(
              onPressed: _fetchProfile,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_profile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Profile not found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _fetchProfile,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchProfile();
        await _fetchStats();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Profile header with avatar and name
            ProfileHeader(profile: _profile!),

            const SizedBox(height: 16),

            // Profile stats
            ProfileStatsSection(
              pulsesCreated: _pulsesCreated,
              pulsesJoined: _pulsesJoined,
              connections: _connections,
              onPulsesCreatedTap: () {
                // Navigate to created pulses
              },
              onPulsesJoinedTap: () {
                // Navigate to joined pulses
              },
              onConnectionsTap: () {
                Navigator.pushNamed(context, '/connections');
              },
            ),

            const SizedBox(height: 16),

            // Profile info
            ProfileInfoSection(
              profile: _profile!,
              onEditTap: _navigateToEditProfile,
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

            const SizedBox(height: 16),

            // Settings sections
            SettingsSection(
              title: 'Account Settings',
              children: [
                SettingsItem(
                  title: 'Edit Profile',
                  subtitle: 'Change your profile information',
                  icon: Icons.person_outline,
                  onTap: _navigateToEditProfile,
                ),
                SettingsItem(
                  title: 'Notification Settings',
                  subtitle: 'Manage your notification preferences',
                  icon: Icons.notifications_outlined,
                  onTap: _navigateToNotificationSettings,
                ),
                SettingsItem(
                  title: 'Connections',
                  subtitle: 'Manage your connections',
                  icon: Icons.people_outline,
                  onTap: () {
                    Navigator.pushNamed(context, '/connections');
                  },
                ),
                SettingsItem(
                  title: 'Privacy Settings',
                  subtitle: 'Control your privacy and data sharing',
                  icon: Icons.lock_outline,
                  onTap: _navigateToPrivacySettings,
                  showDivider: false,
                ),
              ],
            ),

            SettingsSection(
              title: 'App Settings',
              children: [
                SettingsItem(
                  title: 'Theme',
                  subtitle: _getThemeModeName(_profile!.themeMode),
                  icon: Icons.palette_outlined,
                  onTap: () {
                    // Show theme selection dialog
                    _showThemeSelectionDialog();
                  },
                  trailing: Icon(
                    _getThemeModeIcon(_profile!.themeMode),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                SettingsItem(
                  title: 'About',
                  subtitle: 'App information and legal',
                  icon: Icons.info_outline,
                  onTap: () {
                    // Navigate to about screen
                  },
                  showDivider: false,
                ),
              ],
            ),

            SettingsSection(
              title: 'Account',
              showDivider: false,
              children: [
                SettingsItem(
                  title: 'Sign Out',
                  subtitle: 'Sign out of your account',
                  icon: Icons.logout,
                  onTap: _confirmSignOut,
                  iconColor: Colors.red,
                  showDivider: false,
                ),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// Get the name of the theme mode
  String _getThemeModeName(ThemeMode themeMode) {
    switch (themeMode) {
      case ThemeMode.system:
        return 'System default';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  /// Get the icon for the theme mode
  IconData _getThemeModeIcon(ThemeMode themeMode) {
    switch (themeMode) {
      case ThemeMode.system:
        return Icons.brightness_auto;
      case ThemeMode.light:
        return Icons.brightness_5;
      case ThemeMode.dark:
        return Icons.brightness_3;
    }
  }

  /// Show theme selection dialog
  Future<void> _showThemeSelectionDialog() async {
    if (_profile == null) return;

    // Get the services before the async gap
    final supabaseService =
        Provider.of<SupabaseService>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    final ThemeMode? result = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose Theme'),
        children: [
          RadioListTile<ThemeMode>(
            title: const Text('System default'),
            value: ThemeMode.system,
            groupValue: _profile!.themeMode,
            onChanged: (value) => Navigator.pop(context, value),
            secondary: const Icon(Icons.brightness_auto),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Light'),
            value: ThemeMode.light,
            groupValue: _profile!.themeMode,
            onChanged: (value) => Navigator.pop(context, value),
            secondary: const Icon(Icons.brightness_5),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Dark'),
            value: ThemeMode.dark,
            groupValue: _profile!.themeMode,
            onChanged: (value) => Navigator.pop(context, value),
            secondary: const Icon(Icons.brightness_3),
          ),
        ],
      ),
    );

    if (result != null && result != _profile!.themeMode && mounted) {
      try {
        // Update the theme in the database
        await supabaseService.updateThemeMode(
          _profile!.id,
          result,
        );

        // Update the theme provider
        await themeProvider.setThemeMode(result);

        // Refresh profile
        _fetchProfile();

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Theme updated')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating theme: ${e.toString()}')),
          );
        }
      }
    }
  }
}
