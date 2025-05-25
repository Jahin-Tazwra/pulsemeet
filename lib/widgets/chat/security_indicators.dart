import 'package:flutter/material.dart';

import 'package:pulsemeet/models/encryption_models.dart';

/// Widget for displaying encryption status indicators
class EncryptionStatusIndicator extends StatelessWidget {
  final ConversationEncryptionStatus status;
  final bool showText;
  final double size;

  const EncryptionStatusIndicator({
    super.key,
    required this.status,
    this.showText = false,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Encryption icon
        Icon(
          _getEncryptionIcon(),
          size: size,
          color: _getEncryptionColor(isDark),
        ),

        // Text description (optional)
        if (showText) ...[
          const SizedBox(width: 4),
          Text(
            _getEncryptionText(),
            style: TextStyle(
              fontSize: size * 0.75,
              color: _getEncryptionColor(isDark),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  /// Get encryption icon based on status
  IconData _getEncryptionIcon() {
    if (!status.isEncrypted) {
      return Icons.lock_open;
    }

    switch (status.encryptionLevel) {
      case EncryptionLevel.endToEnd:
        return Icons.verified_user;
      case EncryptionLevel.transport:
        return Icons.lock;
      case EncryptionLevel.none:
        return Icons.lock_open;
    }
  }

  /// Get encryption color based on status
  Color _getEncryptionColor(bool isDark) {
    if (!status.isEncrypted) {
      return Colors.red;
    }

    switch (status.encryptionLevel) {
      case EncryptionLevel.endToEnd:
        return Colors.green;
      case EncryptionLevel.transport:
        return Colors.orange;
      case EncryptionLevel.none:
        return Colors.red;
    }
  }

  /// Get encryption text description
  String _getEncryptionText() {
    if (!status.isEncrypted) {
      return 'Not encrypted';
    }

    switch (status.encryptionLevel) {
      case EncryptionLevel.endToEnd:
        return 'End-to-end encrypted';
      case EncryptionLevel.transport:
        return 'Encrypted';
      case EncryptionLevel.none:
        return 'Not encrypted';
    }
  }
}

/// Widget for displaying security score
class SecurityScoreIndicator extends StatelessWidget {
  final ConversationEncryptionStatus status;
  final bool showPercentage;

  const SecurityScoreIndicator({
    super.key,
    required this.status,
    this.showPercentage = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = status.securityScore;
    final color = _getScoreColor(score);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Security icon
        Icon(
          _getScoreIcon(score),
          size: 16,
          color: color,
        ),

        const SizedBox(width: 4),

        // Score text
        if (showPercentage)
          Text(
            '$score%',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Text(
            status.securityDescription,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  /// Get score color based on value
  Color _getScoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  /// Get score icon based on value
  IconData _getScoreIcon(int score) {
    if (score >= 80) return Icons.security;
    if (score >= 60) return Icons.warning;
    return Icons.error;
  }
}

/// Widget for displaying verification status
class VerificationStatusIndicator extends StatelessWidget {
  final bool isVerified;
  final VoidCallback? onTap;

  const VerificationStatusIndicator({
    super.key,
    required this.isVerified,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isVerified
              ? Colors.green.withOpacity(0.1)
              : Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isVerified ? Colors.green : Colors.orange,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isVerified ? Icons.verified : Icons.warning,
              size: 12,
              color: isVerified ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 4),
            Text(
              isVerified ? 'Verified' : 'Unverified',
              style: TextStyle(
                fontSize: 10,
                color: isVerified ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget for displaying disappearing message timer
class DisappearingMessageIndicator extends StatelessWidget {
  final DisappearingMessageSettings settings;
  final Duration? timeRemaining;

  const DisappearingMessageIndicator({
    super.key,
    required this.settings,
    this.timeRemaining,
  });

  @override
  Widget build(BuildContext context) {
    if (!settings.enabled) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer,
            size: 12,
            color: Colors.blue,
          ),
          const SizedBox(width: 4),
          Text(
            timeRemaining != null
                ? _formatTimeRemaining(timeRemaining!)
                : settings.formattedDuration,
            style: TextStyle(
              fontSize: 10,
              color: Colors.blue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Format time remaining for display
  String _formatTimeRemaining(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}

/// Widget for displaying message encryption status
class MessageEncryptionIndicator extends StatelessWidget {
  final bool isEncrypted;
  final bool isVerified;
  final double size;

  const MessageEncryptionIndicator({
    super.key,
    required this.isEncrypted,
    this.isVerified = false,
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (!isEncrypted) {
      return const SizedBox.shrink();
    }

    return Icon(
      isVerified ? Icons.verified_user : Icons.lock,
      size: size,
      color: isVerified ? Colors.green : Colors.grey[600],
    );
  }
}

/// Widget for displaying security warning
class SecurityWarningBanner extends StatelessWidget {
  final String message;
  final SecurityEventType eventType;
  final VoidCallback? onDismiss;
  final VoidCallback? onAction;
  final String? actionText;

  const SecurityWarningBanner({
    super.key,
    required this.message,
    required this.eventType,
    this.onDismiss,
    this.onAction,
    this.actionText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getWarningColor();

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        children: [
          Icon(
            _getWarningIcon(),
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getWarningTitle(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (onAction != null && actionText != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: Text(
                actionText!,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
          if (onDismiss != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close, color: color, size: 16),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }

  /// Get warning color based on event type
  Color _getWarningColor() {
    switch (eventType) {
      case SecurityEventType.encryptionFailure:
        return Colors.red;
      case SecurityEventType.securityWarning:
        return Colors.orange;
      case SecurityEventType.keyRotation:
        return Colors.blue;
      case SecurityEventType.verification:
        return Colors.green;
      case SecurityEventType.keyExchange:
        return Colors.purple;
    }
  }

  /// Get warning icon based on event type
  IconData _getWarningIcon() {
    switch (eventType) {
      case SecurityEventType.encryptionFailure:
        return Icons.error;
      case SecurityEventType.securityWarning:
        return Icons.warning;
      case SecurityEventType.keyRotation:
        return Icons.refresh;
      case SecurityEventType.verification:
        return Icons.verified_user;
      case SecurityEventType.keyExchange:
        return Icons.key;
    }
  }

  /// Get warning title based on event type
  String _getWarningTitle() {
    switch (eventType) {
      case SecurityEventType.encryptionFailure:
        return 'Encryption Failed';
      case SecurityEventType.securityWarning:
        return 'Security Warning';
      case SecurityEventType.keyRotation:
        return 'Keys Updated';
      case SecurityEventType.verification:
        return 'Verification Required';
      case SecurityEventType.keyExchange:
        return 'Key Exchange';
    }
  }
}
