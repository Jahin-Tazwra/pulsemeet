import 'package:flutter/material.dart';

/// A reusable error widget that follows PulseMeet's design system
class CustomErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData? icon;
  final String? retryText;
  final bool showIcon;
  final Color? iconColor;
  final Color? textColor;

  const CustomErrorWidget({
    super.key,
    required this.message,
    this.onRetry,
    this.icon,
    this.retryText,
    this.showIcon = true,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final errorColor = iconColor ?? theme.colorScheme.error;
    final messageColor =
        textColor ?? (isDark ? Colors.grey[300] : Colors.grey[700]);

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(
              icon ?? Icons.error_outline,
              size: 64,
              color: errorColor,
            ),
            const SizedBox(height: 16),
          ],
          Text(
            message,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: messageColor,
            ),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(retryText ?? 'Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact error widget for inline use
class CompactErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final Color? color;

  const CompactErrorWidget({
    super.key,
    required this.message,
    this.onRetry,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = color ?? theme.colorScheme.error;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline,
          color: errorColor,
          size: 16,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: errorColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRetry,
            child: Icon(
              Icons.refresh,
              color: errorColor,
              size: 16,
            ),
          ),
        ],
      ],
    );
  }
}

/// An error banner that can be shown at the top of screens
class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;
  final Color? backgroundColor;
  final Color? textColor;

  const ErrorBanner({
    super.key,
    required this.message,
    this.onDismiss,
    this.onRetry,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.errorContainer;
    final txtColor = textColor ?? theme.colorScheme.onErrorContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.error.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning,
            color: txtColor,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: txtColor,
              ),
            ),
          ),
          if (onRetry != null) ...[
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: txtColor,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Retry'),
            ),
          ],
          if (onDismiss != null) ...[
            IconButton(
              onPressed: onDismiss,
              icon: Icon(
                Icons.close,
                color: txtColor,
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A network error widget with specific messaging
class NetworkErrorWidget extends StatelessWidget {
  final VoidCallback? onRetry;
  final String? customMessage;

  const NetworkErrorWidget({
    super.key,
    this.onRetry,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    return CustomErrorWidget(
      message: customMessage ??
          'Unable to connect to the internet.\nPlease check your connection and try again.',
      icon: Icons.wifi_off,
      onRetry: onRetry,
      retryText: 'Try Again',
    );
  }
}

/// A generic server error widget
class ServerErrorWidget extends StatelessWidget {
  final VoidCallback? onRetry;
  final String? customMessage;

  const ServerErrorWidget({
    super.key,
    this.onRetry,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    return CustomErrorWidget(
      message: customMessage ??
          'Something went wrong on our end.\nPlease try again in a moment.',
      icon: Icons.cloud_off,
      onRetry: onRetry,
      retryText: 'Retry',
    );
  }
}
