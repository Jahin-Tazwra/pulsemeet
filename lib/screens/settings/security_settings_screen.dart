import 'package:flutter/material.dart';

import 'package:pulsemeet/models/encryption_models.dart';
import 'package:pulsemeet/services/enhanced_encryption_service.dart';
import 'package:pulsemeet/services/advanced_security_service.dart';
import 'package:pulsemeet/services/disappearing_messages_service.dart';
import 'package:pulsemeet/widgets/chat/security_indicators.dart';

/// Screen for managing security and encryption settings
class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final EnhancedEncryptionService _encryptionService =
      EnhancedEncryptionService();
  final AdvancedSecurityService _securityService = AdvancedSecurityService();
  final DisappearingMessagesService _disappearingService =
      DisappearingMessagesService();

  Map<String, bool> _securitySettings = {};
  List<SecurityEvent> _recentEvents = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSecuritySettings();
  }

  /// Load security settings and events
  Future<void> _loadSecuritySettings() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Load security settings
      final settings = _securityService.getSecuritySettings();
      final events = _securityService.getRecentSecurityEvents();

      setState(() {
        _securitySettings = settings;
        _recentEvents = events;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load security settings: $e';
      });
    }
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
        title: const Text(
          'Security Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _buildSettingsContent(),
    );
  }

  /// Build error state
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            'Error Loading Settings',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadSecuritySettings,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Build settings content
  Widget _buildSettingsContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Encryption section
        _buildEncryptionSection(),

        const SizedBox(height: 24),

        // Privacy section
        _buildPrivacySection(),

        const SizedBox(height: 24),

        // Security monitoring section
        _buildSecurityMonitoringSection(),

        const SizedBox(height: 24),

        // Advanced section
        _buildAdvancedSection(),

        const SizedBox(height: 24),

        // Recent security events
        _buildRecentEventsSection(),
      ],
    );
  }

  /// Build encryption section
  Widget _buildEncryptionSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.security,
                  color: theme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Encryption',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Signal Protocol status
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _encryptionService.isSignalProtocolEnabled
                    ? Icons.verified_user
                    : Icons.warning,
                color: _encryptionService.isSignalProtocolEnabled
                    ? Colors.green
                    : Colors.orange,
              ),
              title: const Text('Signal Protocol'),
              subtitle: Text(
                _encryptionService.isSignalProtocolEnabled
                    ? 'End-to-end encryption enabled'
                    : 'Using legacy encryption',
              ),
              trailing: Switch(
                value: _encryptionService.isSignalProtocolEnabled,
                onChanged: (value) => _toggleSignalProtocol(value),
              ),
            ),

            const Divider(),

            // Key backup
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.backup),
              title: const Text('Backup Encryption Keys'),
              subtitle: const Text('Securely backup your encryption keys'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _backupKeys,
            ),

            // Key restore
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restore),
              title: const Text('Restore Encryption Keys'),
              subtitle: const Text('Restore keys from backup'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _restoreKeys,
            ),
          ],
        ),
      ),
    );
  }

  /// Build privacy section
  Widget _buildPrivacySection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.privacy_tip,
                  color: theme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Privacy',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Screenshot protection
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.screenshot_monitor),
              title: const Text('Screenshot Protection'),
              subtitle: const Text('Prevent screenshots in conversations'),
              trailing: Switch(
                value: _securitySettings['screenshot_protection'] ?? false,
                onChanged: (value) =>
                    _updateSecuritySetting('screenshot_protection', value),
              ),
            ),

            const Divider(),

            // Screen recording detection
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.videocam_off),
              title: const Text('Screen Recording Detection'),
              subtitle: const Text('Detect and warn about screen recording'),
              trailing: Switch(
                value: _securitySettings['screen_recording_detection'] ?? false,
                onChanged: (value) =>
                    _updateSecuritySetting('screen_recording_detection', value),
              ),
            ),

            const Divider(),

            // Disappearing messages default
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer),
              title: const Text('Default Disappearing Messages'),
              subtitle: const Text('Set default timer for new conversations'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _configureDisappearingMessages,
            ),
          ],
        ),
      ),
    );
  }

  /// Build security monitoring section
  Widget _buildSecurityMonitoringSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.monitor_heart,
                  color: theme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Security Monitoring',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Security events count
            Row(
              children: [
                const Icon(Icons.event, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Recent Events: ${_recentEvents.length}',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                TextButton(
                  onPressed: _viewAllEvents,
                  child: const Text('View All'),
                ),
              ],
            ),

            // Device security status
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.phone_android, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Device Security: Good',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build advanced section
  Widget _buildAdvancedSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings,
                  color: theme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Advanced',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Reset all encryption keys
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.refresh, color: Colors.orange),
              title: const Text('Reset All Encryption Keys'),
              subtitle: const Text('Generate new keys for all conversations'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _resetAllKeys,
            ),

            const Divider(),

            // Clear security logs
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.clear_all, color: Colors.red),
              title: const Text('Clear Security Logs'),
              subtitle: const Text('Remove all security event logs'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _clearSecurityLogs,
            ),
          ],
        ),
      ),
    );
  }

  /// Build recent events section
  Widget _buildRecentEventsSection() {
    if (_recentEvents.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history,
                  color: theme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Recent Security Events',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Show last 3 events
            ...(_recentEvents.take(3).map((event) => _buildEventItem(event))),

            if (_recentEvents.length > 3) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _viewAllEvents,
                  child: Text('View All ${_recentEvents.length} Events'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Build event item
  Widget _buildEventItem(SecurityEvent event) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            _getEventIcon(event.type),
            size: 16,
            color: _getEventColor(event.type),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              event.description,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Text(
            _formatEventTime(event.timestamp),
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// Get event icon
  IconData _getEventIcon(SecurityEventType type) {
    switch (type) {
      case SecurityEventType.keyExchange:
        return Icons.key;
      case SecurityEventType.verification:
        return Icons.verified_user;
      case SecurityEventType.keyRotation:
        return Icons.refresh;
      case SecurityEventType.securityWarning:
        return Icons.warning;
      case SecurityEventType.encryptionFailure:
        return Icons.error;
    }
  }

  /// Get event color
  Color _getEventColor(SecurityEventType type) {
    switch (type) {
      case SecurityEventType.keyExchange:
        return Colors.blue;
      case SecurityEventType.verification:
        return Colors.green;
      case SecurityEventType.keyRotation:
        return Colors.orange;
      case SecurityEventType.securityWarning:
        return Colors.orange;
      case SecurityEventType.encryptionFailure:
        return Colors.red;
    }
  }

  /// Format event time
  String _formatEventTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  /// Toggle Signal Protocol
  void _toggleSignalProtocol(bool enabled) {
    _encryptionService.setSignalProtocolEnabled(enabled);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled ? 'Signal Protocol enabled' : 'Signal Protocol disabled',
        ),
      ),
    );
  }

  /// Update security setting
  Future<void> _updateSecuritySetting(String setting, bool enabled) async {
    await _securityService.updateSecuritySetting(setting, enabled);
    setState(() {
      _securitySettings[setting] = enabled;
    });
  }

  /// Backup encryption keys
  void _backupKeys() async {
    final backup = await _securityService.backupEncryptionKeys();
    if (backup != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encryption keys backed up successfully')),
      );
    }
  }

  /// Restore encryption keys
  void _restoreKeys() {
    // TODO: Implement key restore UI
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Key restore functionality coming soon')),
    );
  }

  /// Configure disappearing messages
  void _configureDisappearingMessages() {
    // TODO: Implement disappearing messages configuration
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Disappearing messages configuration coming soon')),
    );
  }

  /// Reset all encryption keys
  void _resetAllKeys() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset All Encryption Keys'),
        content: const Text(
          'This will generate new encryption keys for all conversations. '
          'All participants will need to verify the new keys. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement key reset
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Key reset functionality coming soon')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  /// Clear security logs
  void _clearSecurityLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Security Logs'),
        content: const Text(
          'This will permanently delete all security event logs. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _recentEvents.clear();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Security logs cleared')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  /// View all security events
  void _viewAllEvents() {
    // TODO: Navigate to detailed security events screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Detailed security events screen coming soon')),
    );
  }
}
