import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A widget that displays a date separator in a chat
class DateSeparator extends StatelessWidget {
  final DateTime date;
  
  const DateSeparator({
    super.key,
    required this.date,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Colors.grey.withAlpha(100),
              thickness: 0.5,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 4.0,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(10),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                _formatDate(date),
                style: TextStyle(
                  fontSize: 12.0,
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Colors.grey.withAlpha(100),
              thickness: 0.5,
            ),
          ),
        ],
      ),
    );
  }
  
  /// Format the date
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    
    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == yesterday) {
      return 'Yesterday';
    } else if (now.difference(date).inDays < 7) {
      // Within the last week, show day name
      return DateFormat('EEEE').format(date); // e.g., "Monday"
    } else if (date.year == now.year) {
      // Same year, show month and day
      return DateFormat('MMMM d').format(date); // e.g., "April 15"
    } else {
      // Different year, show full date
      return DateFormat('MMMM d, y').format(date); // e.g., "April 15, 2023"
    }
  }
}
