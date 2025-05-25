import 'package:flutter/material.dart';

import 'package:pulsemeet/models/message.dart';

/// Widget for displaying system messages (user joined, left, etc.)
class SystemMessageWidget extends StatelessWidget {
  final Message message;

  const SystemMessageWidget({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E5EA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getSystemMessageIcon(),
                size: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  message.content,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get icon for system message based on content
  IconData _getSystemMessageIcon() {
    final content = message.content.toLowerCase();
    
    if (content.contains('joined')) {
      return Icons.person_add;
    } else if (content.contains('left')) {
      return Icons.person_remove;
    } else if (content.contains('created')) {
      return Icons.group_add;
    } else if (content.contains('changed')) {
      return Icons.edit;
    } else if (content.contains('call')) {
      return Icons.call;
    } else {
      return Icons.info_outline;
    }
  }
}
