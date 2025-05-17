import 'package:flutter/material.dart';
import 'package:pulsemeet/models/chat_message.dart';

/// A widget that displays reactions to a message
class MessageReactions extends StatelessWidget {
  final List<MessageReaction> reactions;
  final VoidCallback onReactionTap;
  final Alignment alignment;

  const MessageReactions({
    super.key,
    required this.reactions,
    required this.onReactionTap,
    this.alignment = Alignment.centerLeft,
  });

  @override
  Widget build(BuildContext context) {
    // Group reactions by emoji
    final Map<String, int> reactionCounts = {};
    for (final reaction in reactions) {
      reactionCounts[reaction.emoji] = (reactionCounts[reaction.emoji] ?? 0) + 1;
    }
    
    return GestureDetector(
      onTap: onReactionTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 8.0,
          vertical: 4.0,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Wrap(
          alignment: alignment == Alignment.centerRight 
              ? WrapAlignment.end 
              : WrapAlignment.start,
          spacing: 4.0,
          children: reactionCounts.entries.map((entry) {
            return _buildReactionChip(context, entry.key, entry.value);
          }).toList(),
        ),
      ),
    );
  }
  
  /// Build a reaction chip
  Widget _buildReactionChip(BuildContext context, String emoji, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6.0,
        vertical: 2.0,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            emoji,
            style: const TextStyle(
              fontSize: 14.0,
            ),
          ),
          if (count > 1) ...[
            const SizedBox(width: 2.0),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 12.0,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
