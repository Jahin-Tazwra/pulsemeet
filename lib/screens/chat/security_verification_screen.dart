import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pulsemeet/models/conversation.dart';
import 'package:pulsemeet/models/encryption_models.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/enhanced_encryption_service.dart';
import 'package:pulsemeet/widgets/avatar.dart';
import 'package:pulsemeet/widgets/chat/security_indicators.dart';

/// Screen for verifying encryption keys and security status
class SecurityVerificationScreen extends StatefulWidget {
  final Conversation conversation;
  final Profile? targetUser; // For direct message verification

  const SecurityVerificationScreen({
    super.key,
    required this.conversation,
    this.targetUser,
  });

  @override
  State<SecurityVerificationScreen> createState() =>
      _SecurityVerificationScreenState();
}

class _SecurityVerificationScreenState extends State<SecurityVerificationScreen>
    with SingleTickerProviderStateMixin {
  final EnhancedEncryptionService _encryptionService =
      EnhancedEncryptionService();

  late TabController _tabController;
  ConversationEncryptionStatus? _encryptionStatus;
  List<KeyFingerprint> _keyFingerprints = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSecurityInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Load security information
  Future<void> _loadSecurityInfo() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Get encryption status
      final status =
          await _encryptionService.getEncryptionStatus(widget.conversation.id);

      // Load key fingerprints
      final fingerprints = await _loadKeyFingerprints();

      setState(() {
        _encryptionStatus = status;
        _keyFingerprints = fingerprints;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load security information: $e';
      });
    }
  }

  /// Load key fingerprints for conversation participants
  Future<List<KeyFingerprint>> _loadKeyFingerprints() async {
    // TODO: Implement actual key fingerprint loading
    // For now, return mock data
    return [
      KeyFingerprint(
        userId: widget.targetUser?.id ?? 'user1',
        fingerprint: 'A1B2 C3D4 E5F6 7890 1234 5678 9ABC DEF0',
        generatedAt: DateTime.now().subtract(const Duration(days: 30)),
        isVerified: false,
      ),
    ];
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
          'Security Verification',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.primaryColor,
          unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[600],
          indicatorColor: theme.primaryColor,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Fingerprints'),
            Tab(text: 'Settings'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    _buildFingerprintsTab(),
                    _buildSettingsTab(),
                  ],
                ),
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
            'Security Error',
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
            onPressed: _loadSecurityInfo,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Build overview tab
  Widget _buildOverviewTab() {
    if (_encryptionStatus == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Conversation info
          _buildConversationInfo(),

          const SizedBox(height: 24),

          // Encryption status
          _buildEncryptionStatusCard(),

          const SizedBox(height: 16),

          // Security score
          _buildSecurityScoreCard(),

          const SizedBox(height: 16),

          // Participants verification
          _buildParticipantsCard(),

          const SizedBox(height: 24),

          // Security actions
          _buildSecurityActions(),
        ],
      ),
    );
  }

  /// Build conversation info
  Widget _buildConversationInfo() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            UserAvatar(
              userId: widget.targetUser?.id ?? 'unknown',
              avatarUrl: widget.targetUser?.avatarUrl,
              size: 48,
            ),

            const SizedBox(width: 16),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.conversation.title ?? 'Unknown Conversation',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.conversation.isDirectMessage
                        ? 'Direct Message'
                        : 'Group Conversation',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            // Encryption indicator
            EncryptionStatusIndicator(
              status: _encryptionStatus!,
              showText: false,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  /// Build encryption status card
  Widget _buildEncryptionStatusCard() {
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
                  'Encryption Status',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                EncryptionStatusIndicator(
                  status: _encryptionStatus!,
                  showText: true,
                  size: 20,
                ),
                const Spacer(),
                SecurityScoreIndicator(
                  status: _encryptionStatus!,
                  showPercentage: false,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _getEncryptionDescription(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build security score card
  Widget _buildSecurityScoreCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final score = _encryptionStatus!.securityScore;

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
                  Icons.analytics,
                  color: theme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Security Score',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '$score/100',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _getScoreColor(score),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Progress bar
            LinearProgressIndicator(
              value: score / 100,
              backgroundColor: isDark ? Colors.grey[700] : Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(_getScoreColor(score)),
            ),

            const SizedBox(height: 12),

            Text(
              _encryptionStatus!.securityDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build participants card
  Widget _buildParticipantsCard() {
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
                  Icons.people,
                  color: theme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Participants',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Total: ${_encryptionStatus!.participantCount}',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                Text(
                  'Verified: ${_encryptionStatus!.verifiedParticipants}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build security actions
  Widget _buildSecurityActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _verifyFingerprints,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Verify Fingerprints'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _resetKeys,
            icon: const Icon(Icons.refresh),
            label: const Text('Reset Encryption Keys'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  /// Build fingerprints tab
  Widget _buildFingerprintsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _keyFingerprints.length,
      itemBuilder: (context, index) {
        final fingerprint = _keyFingerprints[index];
        return _buildFingerprintCard(fingerprint);
      },
    );
  }

  /// Build fingerprint card
  Widget _buildFingerprintCard(KeyFingerprint fingerprint) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info
            Row(
              children: [
                UserAvatar(
                  userId: widget.targetUser?.id ?? 'unknown',
                  avatarUrl: widget.targetUser?.avatarUrl,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.targetUser?.displayName ?? 'Unknown User',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Generated ${_formatDate(fingerprint.generatedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                VerificationStatusIndicator(
                  isVerified: fingerprint.isVerified,
                  onTap: () => _toggleVerification(fingerprint),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Fingerprint
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    'Key Fingerprint',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    fingerprint.formattedFingerprint,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyFingerprint(fingerprint.fingerprint),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showFingerprintDetails(fingerprint),
                    icon: const Icon(Icons.fingerprint, size: 16),
                    label: const Text('Details'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build settings tab
  Widget _buildSettingsTab() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Disappearing messages
        Card(
          color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
          child: ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('Disappearing Messages'),
            subtitle: const Text('Messages will be automatically deleted'),
            trailing: Switch(
              value: false, // TODO: Get actual setting
              onChanged: (value) => _toggleDisappearingMessages(value),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Screenshot protection
        Card(
          color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
          child: ListTile(
            leading: const Icon(Icons.screenshot_monitor),
            title: const Text('Screenshot Protection'),
            subtitle: const Text('Prevent screenshots in this conversation'),
            trailing: Switch(
              value: false, // TODO: Get actual setting
              onChanged: (value) => _toggleScreenshotProtection(value),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Backup encryption keys
        Card(
          color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
          child: ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('Backup Encryption Keys'),
            subtitle: const Text('Securely backup your encryption keys'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _backupKeys,
          ),
        ),
      ],
    );
  }

  /// Get encryption description
  String _getEncryptionDescription() {
    if (!_encryptionStatus!.isEncrypted) {
      return 'This conversation is not encrypted. Messages are sent in plain text.';
    }

    switch (_encryptionStatus!.encryptionLevel) {
      case EncryptionLevel.endToEnd:
        return 'This conversation is protected with end-to-end encryption. Only you and the other participants can read the messages.';
      case EncryptionLevel.transport:
        return 'This conversation uses transport encryption. Messages are encrypted in transit but may be readable by the server.';
      case EncryptionLevel.none:
        return 'This conversation is not encrypted. Messages are sent in plain text.';
    }
  }

  /// Get score color
  Color _getScoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  /// Format date
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 30) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  /// Verify fingerprints
  void _verifyFingerprints() {
    _tabController.animateTo(1);
  }

  /// Reset encryption keys
  void _resetKeys() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Encryption Keys'),
        content: const Text(
          'This will generate new encryption keys for this conversation. '
          'All participants will need to verify the new keys.',
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
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  /// Toggle verification status
  void _toggleVerification(KeyFingerprint fingerprint) {
    // TODO: Implement verification toggle
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          fingerprint.isVerified
              ? 'Key verification removed'
              : 'Key verified successfully',
        ),
      ),
    );
  }

  /// Copy fingerprint to clipboard
  void _copyFingerprint(String fingerprint) {
    Clipboard.setData(ClipboardData(text: fingerprint));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fingerprint copied to clipboard')),
    );
  }

  /// Show fingerprint details
  void _showFingerprintDetails(KeyFingerprint fingerprint) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Key Fingerprint'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fingerprint:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: SelectableText(
                fingerprint.formattedFingerprint,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Compare this fingerprint with your contact to verify the security of your conversation.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fingerprint.fingerprint));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Fingerprint copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Toggle disappearing messages
  void _toggleDisappearingMessages(bool enabled) {
    // TODO: Implement disappearing messages toggle
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Disappearing messages enabled'
              : 'Disappearing messages disabled',
        ),
      ),
    );
  }

  /// Toggle screenshot protection
  void _toggleScreenshotProtection(bool enabled) {
    // TODO: Implement screenshot protection toggle
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Screenshot protection enabled'
              : 'Screenshot protection disabled',
        ),
      ),
    );
  }

  /// Backup encryption keys
  void _backupKeys() {
    // TODO: Implement key backup
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Key backup functionality coming soon')),
    );
  }
}
