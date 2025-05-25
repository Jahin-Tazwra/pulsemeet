import 'package:flutter/material.dart';

import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/widgets/avatar.dart';

/// Widget for displaying mention suggestions
class MentionSuggestions extends StatelessWidget {
  final List<Profile> suggestions;
  final String query;
  final Function(Profile) onMentionSelected;

  const MentionSuggestions({
    super.key,
    required this.suggestions,
    required this.query,
    required this.onMentionSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            width: 0.5,
          ),
        ),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final user = suggestions[index];
          return _buildSuggestionItem(context, user, isDark);
        },
      ),
    );
  }

  /// Build individual suggestion item
  Widget _buildSuggestionItem(BuildContext context, Profile user, bool isDark) {
    final theme = Theme.of(context);
    final displayName = user.displayName ?? user.username ?? 'Unknown';
    final username = user.username ?? '';

    return InkWell(
      onTap: () => onMentionSelected(user),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar
            UserAvatar(
              userId: user.id,
              avatarUrl: user.avatarUrl,
              size: 36,
            ),

            const SizedBox(width: 12),

            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display name
                  Text(
                    displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Username
                  if (username.isNotEmpty && username != displayName)
                    Text(
                      '@$username',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Mention indicator
            Icon(
              Icons.alternate_email,
              size: 16,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget for displaying mention suggestions with search highlighting
class HighlightedMentionSuggestions extends StatelessWidget {
  final List<Profile> suggestions;
  final String query;
  final Function(Profile) onMentionSelected;

  const HighlightedMentionSuggestions({
    super.key,
    required this.suggestions,
    required this.query,
    required this.onMentionSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.alternate_email,
                  size: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Text(
                  'Mention someone',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Suggestions list
          Expanded(
            child: ListView.builder(
              itemCount: suggestions.length,
              itemBuilder: (context, index) {
                final user = suggestions[index];
                return _buildHighlightedSuggestionItem(context, user, isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Build suggestion item with query highlighting
  Widget _buildHighlightedSuggestionItem(
      BuildContext context, Profile user, bool isDark) {
    final theme = Theme.of(context);
    final displayName = user.displayName ?? user.username ?? 'Unknown';
    final username = user.username ?? '';

    return InkWell(
      onTap: () => onMentionSelected(user),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar
            UserAvatar(
              userId: user.id,
              avatarUrl: user.avatarUrl,
              size: 36,
            ),

            const SizedBox(width: 12),

            // User info with highlighting
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display name with highlighting
                  RichText(
                    text: _buildHighlightedText(
                      displayName,
                      query,
                      theme.textTheme.bodyMedium?.copyWith(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                          ) ??
                          const TextStyle(),
                      theme.primaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Username with highlighting
                  if (username.isNotEmpty && username != displayName)
                    RichText(
                      text: _buildHighlightedText(
                        '@$username',
                        query,
                        theme.textTheme.bodySmall?.copyWith(
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600],
                            ) ??
                            const TextStyle(),
                        theme.primaryColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Mention indicator
            Icon(
              Icons.alternate_email,
              size: 16,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }

  /// Build text with query highlighting
  TextSpan _buildHighlightedText(
    String text,
    String query,
    TextStyle baseStyle,
    Color highlightColor,
  ) {
    if (query.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];

    int start = 0;
    int index = lowerText.indexOf(lowerQuery);

    while (index != -1) {
      // Add text before match
      if (index > start) {
        spans.add(TextSpan(
          text: text.substring(start, index),
          style: baseStyle,
        ));
      }

      // Add highlighted match
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: baseStyle.copyWith(
          backgroundColor: highlightColor.withOpacity(0.3),
          fontWeight: FontWeight.bold,
        ),
      ));

      start = index + query.length;
      index = lowerText.indexOf(lowerQuery, start);
    }

    // Add remaining text
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: baseStyle,
      ));
    }

    return TextSpan(children: spans);
  }
}
