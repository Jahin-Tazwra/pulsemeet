import 'package:flutter/material.dart';
import 'package:pulsemeet/models/conversation.dart';

class TypingIndicator extends StatefulWidget {
  final List<String> typingUsers;
  final Conversation conversation;
  final Color? color;

  const TypingIndicator({
    super.key,
    required this.typingUsers,
    required this.conversation,
    this.color,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _dotsController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _dotsAnimation;

  bool _isVisible = false;
  bool _shouldShow = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _dotsAnimation = CurvedAnimation(
      parent: _dotsController,
      curve: Curves.easeInOut,
    );

    _shouldShow = widget.typingUsers.isNotEmpty;
    if (_shouldShow) {
      _isVisible = true;
      _fadeController.forward();
      _dotsController.repeat();
    } else {
      _isVisible = false;
    }
  }

  @override
  void didUpdateWidget(TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    final shouldShowNow = widget.typingUsers.isNotEmpty;

    if (shouldShowNow != _shouldShow) {
      _shouldShow = shouldShowNow;

      if (_shouldShow) {
        if (!_isVisible) {
          setState(() {
            _isVisible = true;
          });
        }
        _fadeController.forward();
        _dotsController.repeat();
      } else {
        _dotsController.stop();
        _fadeController.reverse().then((_) {
          if (mounted) {
            setState(() {
              _isVisible = false;
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typingCount = widget.typingUsers.length;

    // CRITICAL FIX: Don't show indicator when no one is typing
    if (!_isVisible || typingCount == 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    String typingText;

    if (typingCount == 1) {
      typingText =
          widget.conversation.isDirectMessage ? 'Typing' : 'Someone is typing';
    } else {
      typingText = '$typingCount people are typing';
    }

    final baseColor =
        widget.color ?? (isDark ? Colors.grey[300] : Colors.grey[800]);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                typingText,
                style: TextStyle(
                  fontSize: 13.5,
                  color: baseColor,
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedBuilder(
                animation: _dotsAnimation,
                builder: (context, child) {
                  int dotCount = ((_dotsAnimation.value * 3) % 4).floor();
                  String dots = '.' * dotCount;
                  return Text(
                    dots,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: baseColor,
                      fontWeight: FontWeight.w500,
                      fontStyle: FontStyle.italic,
                      decoration: TextDecoration.none,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
