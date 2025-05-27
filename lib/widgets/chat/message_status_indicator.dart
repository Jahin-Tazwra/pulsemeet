import 'package:flutter/material.dart';
import 'package:pulsemeet/models/message.dart';

/// A widget that displays the status of a message with animations
class MessageStatusIndicator extends StatefulWidget {
  final MessageStatus status;
  final Color? color;
  final double size;

  const MessageStatusIndicator({
    super.key,
    required this.status,
    this.color,
    this.size = 12.0,
  });

  @override
  State<MessageStatusIndicator> createState() => _MessageStatusIndicatorState();
}

class _MessageStatusIndicatorState extends State<MessageStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Create animation
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    // Start animation if not in sending or failed state
    if (widget.status != MessageStatus.sending &&
        widget.status != MessageStatus.failed) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(MessageStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ENHANCED DEBUG: Log all status changes
    if (oldWidget.status != widget.status) {
      debugPrint(
          '🎯 MessageStatusIndicator: Status changed from ${oldWidget.status} to ${widget.status}');

      // Reset and start animation for status changes
      if (widget.status != MessageStatus.sending &&
          widget.status != MessageStatus.failed) {
        _controller.reset();
        _controller.forward();
        debugPrint(
            '🎯 MessageStatusIndicator: Animation started for status ${widget.status}');
      }
    } else {
      debugPrint(
          '🎯 MessageStatusIndicator: Widget updated but status unchanged: ${widget.status}');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use a more visible default color - white with higher opacity for better contrast
    final Color iconColor = widget.color ??
        Colors.white.withAlpha(230); // 0.9 opacity for better visibility

    switch (widget.status) {
      case MessageStatus.sending:
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(iconColor),
          ),
        );

      case MessageStatus.sent:
        return AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Transform.scale(
              scale: _animation.value,
              child: Icon(
                Icons.check,
                size: widget.size,
                color: iconColor,
              ),
            );
          },
        );

      case MessageStatus.delivered:
        return AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Transform.scale(
              scale: _animation.value,
              child: Icon(
                Icons.done_all,
                size: widget.size,
                color: iconColor,
              ),
            );
          },
        );

      case MessageStatus.read:
        return AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            // Interpolate color from gray to blue
            final Color currentColor = ColorTween(
              begin: iconColor,
              end: Theme.of(context).colorScheme.primary,
            ).evaluate(_animation)!;

            return Icon(
              Icons.done_all,
              size: widget.size,
              color: currentColor,
            );
          },
        );

      case MessageStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: widget.size,
              color: Colors.red,
            ),
            const SizedBox(width: 4),
            Text(
              'Failed',
              style: TextStyle(
                fontSize: widget.size * 0.8,
                color: Colors.red,
              ),
            ),
          ],
        );
    }
  }
}
