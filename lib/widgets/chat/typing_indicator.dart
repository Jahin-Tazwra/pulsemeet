import 'package:flutter/material.dart';
import 'package:pulsemeet/models/profile.dart';

/// A widget that displays a typing indicator
class TypingIndicator extends StatefulWidget {
  final List<Profile> typingUsers;
  final Color? color;

  const TypingIndicator({
    super.key,
    required this.typingUsers,
    this.color,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Create animations for the dots
    _animations = List.generate(
      3,
      (index) => Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            index * 0.2,
            0.6 + index * 0.2,
            curve: Curves.easeInOut,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If no one is typing, return an empty container
    if (widget.typingUsers.isEmpty) {
      return const SizedBox.shrink();
    }

    // Get the names of typing users
    final names = widget.typingUsers
        .map((user) => user.displayName ?? user.username ?? 'Someone')
        .toList();

    // Create the typing text
    String typingText;
    if (names.length == 1) {
      typingText = '${names[0]} is typing';
    } else if (names.length == 2) {
      typingText = '${names[0]} and ${names[1]} are typing';
    } else if (names.length == 3) {
      typingText = '${names[0]}, ${names[1]}, and ${names[2]} are typing';
    } else {
      typingText = '${names.length} people are typing';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            typingText,
            style: TextStyle(
              fontSize: 12.0,
              color: widget.color ?? Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 4.0),
          // Animated dots
          ...List.generate(
            3,
            (index) => AnimatedBuilder(
              animation: _animations[index],
              builder: (context, child) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -3.0 * _animations[index].value),
                    child: Text(
                      '.',
                      style: TextStyle(
                        fontSize: 12.0,
                        color: widget.color ?? Colors.grey[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
