import 'package:flutter/material.dart';
import 'package:pulsemeet/services/encrypted_message_service.dart';
import 'package:pulsemeet/models/encryption_key.dart';

/// Widget that displays encryption status for conversations
class EncryptionIndicator extends StatelessWidget {
  final EncryptionStatus status;
  final bool isLarge;
  final VoidCallback? onTap;

  const EncryptionIndicator({
    super.key,
    required this.status,
    this.isLarge = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    IconData icon;
    Color color;
    String tooltip;

    switch (status) {
      case EncryptionStatus.enabled:
        icon = Icons.lock;
        color = Colors.green;
        tooltip = 'End-to-end encrypted';
        break;
      case EncryptionStatus.disabled:
        icon = Icons.lock_open;
        color = Colors.orange;
        tooltip = 'Encryption disabled';
        break;
      case EncryptionStatus.unavailable:
        icon = Icons.lock_outline;
        color = isDark ? Colors.grey[400]! : Colors.grey[600]!;
        tooltip = 'Encryption unavailable';
        break;
    }

    final size = isLarge ? 24.0 : 16.0;

    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Icon(
          icon,
          size: size,
          color: color,
        ),
      ),
    );
  }
}

/// Widget that shows encryption status in message bubbles
class MessageEncryptionBadge extends StatelessWidget {
  final bool isEncrypted;
  final bool isDecryptionFailed;

  const MessageEncryptionBadge({
    super.key,
    required this.isEncrypted,
    this.isDecryptionFailed = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isEncrypted && !isDecryptionFailed) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    IconData icon;
    Color color;
    String tooltip;

    if (isDecryptionFailed) {
      icon = Icons.lock_reset;
      color = Colors.red;
      tooltip = 'Decryption failed';
    } else {
      icon = Icons.lock;
      color = Colors.green;
      tooltip = 'Encrypted';
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Tooltip(
        message: tooltip,
        child: Icon(
          icon,
          size: 12.0,
          color: color,
        ),
      ),
    );
  }
}

/// Widget that shows encryption status in chat app bar
class ChatEncryptionStatus extends StatefulWidget {
  final String conversationId;
  final String conversationType; // 'direct' or 'pulse'

  const ChatEncryptionStatus({
    super.key,
    required this.conversationId,
    required this.conversationType,
  });

  @override
  State<ChatEncryptionStatus> createState() => _ChatEncryptionStatusState();
}

class _ChatEncryptionStatusState extends State<ChatEncryptionStatus> {
  final _encryptedMessageService = EncryptedMessageService();
  EncryptionStatus _status = EncryptionStatus.unavailable;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEncryptionStatus();
  }

  Future<void> _loadEncryptionStatus() async {
    try {
      final conversationType = widget.conversationType == 'direct'
          ? ConversationType.direct
          : ConversationType.pulse;

      final status = await _encryptedMessageService.getEncryptionStatus(
        widget.conversationId,
        conversationType,
      );

      if (mounted) {
        setState(() {
          _status = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading encryption status: $e');
      if (mounted) {
        setState(() {
          _status = EncryptionStatus.unavailable;
          _isLoading = false;
        });
      }
    }
  }

  void _showEncryptionInfo() {
    showDialog(
      context: context,
      builder: (context) => EncryptionInfoDialog(
        status: _status,
        conversationType: widget.conversationType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return EncryptionIndicator(
      status: _status,
      onTap: _showEncryptionInfo,
    );
  }
}

/// Dialog that shows detailed encryption information
class EncryptionInfoDialog extends StatelessWidget {
  final EncryptionStatus status;
  final String conversationType;

  const EncryptionInfoDialog({
    super.key,
    required this.status,
    required this.conversationType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String title;
    String description;
    IconData icon;
    Color iconColor;

    switch (status) {
      case EncryptionStatus.enabled:
        title = 'End-to-End Encrypted';
        description = conversationType == 'direct'
            ? 'Messages in this conversation are secured with end-to-end encryption. Only you and the recipient can read them.'
            : 'Messages in this pulse are secured with end-to-end encryption. Only participants can read them.';
        icon = Icons.lock;
        iconColor = Colors.green;
        break;
      case EncryptionStatus.disabled:
        title = 'Encryption Disabled';
        description =
            'End-to-end encryption is available but currently disabled for this conversation.';
        icon = Icons.lock_open;
        iconColor = Colors.orange;
        break;
      case EncryptionStatus.unavailable:
        title = 'Encryption Unavailable';
        description = conversationType == 'direct'
            ? 'End-to-end encryption is not available for this conversation. The recipient may not support encryption.'
            : 'End-to-end encryption is not available for this pulse.';
        icon = Icons.lock_outline;
        iconColor = Colors.grey;
        break;
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 8),
          Text(title),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          const SizedBox(height: 16),
          if (status == EncryptionStatus.enabled) ...[
            const Text(
              'Security Features:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• AES-256-GCM encryption'),
            const Text('• X25519 key exchange'),
            const Text('• Perfect forward secrecy'),
            const Text('• Zero-knowledge architecture'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Widget that shows encryption setup progress
class EncryptionSetupIndicator extends StatelessWidget {
  final bool isInitializing;
  final String? error;

  const EncryptionSetupIndicator({
    super.key,
    required this.isInitializing,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (!isInitializing && error == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: error != null
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isInitializing) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            const Text('Setting up encryption...'),
          ] else if (error != null) ...[
            Icon(
              Icons.warning,
              size: 16,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Encryption setup failed: $error',
                style: TextStyle(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
