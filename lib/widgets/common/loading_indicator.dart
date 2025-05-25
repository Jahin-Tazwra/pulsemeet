import 'package:flutter/material.dart';

/// A reusable loading indicator widget that follows PulseMeet's design system
class LoadingIndicator extends StatelessWidget {
  final String? message;
  final Color? color;
  final double? size;
  final bool showMessage;

  const LoadingIndicator({
    super.key,
    this.message,
    this.color,
    this.size,
    this.showMessage = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final indicatorColor =
        color ?? (isDark ? Colors.white : theme.colorScheme.primary);

    final defaultMessage = message ?? 'Loading...';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size ?? 32,
          height: size ?? 32,
          child: CircularProgressIndicator(
            color: indicatorColor,
            strokeWidth: 2.5,
          ),
        ),
        if (showMessage && defaultMessage.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            defaultMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// A compact loading indicator for inline use
class CompactLoadingIndicator extends StatelessWidget {
  final Color? color;
  final double size;

  const CompactLoadingIndicator({
    super.key,
    this.color,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final indicatorColor =
        color ?? (isDark ? Colors.white : theme.colorScheme.primary);

    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        color: indicatorColor,
        strokeWidth: 2,
      ),
    );
  }
}

/// A loading overlay that can be placed over other content
class LoadingOverlay extends StatelessWidget {
  final Widget child;
  final bool isLoading;
  final String? message;
  final Color? backgroundColor;

  const LoadingOverlay({
    super.key,
    required this.child,
    required this.isLoading,
    this.message,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: backgroundColor ??
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            child: Center(
              child: LoadingIndicator(
                message: message,
                showMessage: message != null,
              ),
            ),
          ),
      ],
    );
  }
}

/// A linear loading indicator for progress indication
class LinearLoadingIndicator extends StatelessWidget {
  final double? value;
  final Color? color;
  final Color? backgroundColor;
  final String? message;

  const LinearLoadingIndicator({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(
          value: value,
          color: color ?? theme.colorScheme.primary,
          backgroundColor:
              backgroundColor ?? (isDark ? Colors.grey[800] : Colors.grey[300]),
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(
            message!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
