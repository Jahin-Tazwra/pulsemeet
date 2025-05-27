import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:pulsemeet/models/message.dart';

/// Widget for displaying text messages with rich formatting and mentions
class TextMessageWidget extends StatelessWidget {
  final Message message;
  final Color textColor;
  final bool isFromCurrentUser;

  const TextMessageWidget({
    super.key,
    required this.message,
    required this.textColor,
    required this.isFromCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main text content
          _buildTextContent(context),

          // Message metadata (time, status, encryption)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: isFromCurrentUser
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                // Edited indicator
                if (message.isEdited) ...[
                  Text(
                    'edited',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: textColor.withOpacity(0.6),
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                  const SizedBox(width: 4),
                ],

                // Message time
                Text(
                  _formatMessageTime(message.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isFromCurrentUser
                            ? Colors.white.withOpacity(0.7)
                            : Colors.grey[600],
                        fontSize: 11,
                      ),
                ),

                // Note: Encryption indicator and message status are now handled by MessageBubble
                // to avoid duplicate indicators
              ],
            ),
          ),
        ],
      ),
    ));
  }

  /// Build text content with rich formatting
  Widget _buildTextContent(BuildContext context) {
    if (message.isFormatted) {
      return _buildFormattedText(context);
    } else {
      return _buildPlainText(context);
    }
  }

  /// Build plain text with link detection
  Widget _buildPlainText(BuildContext context) {
    final text = message.content;
    final spans = <TextSpan>[];

    // Split text by whitespace to detect URLs and mentions
    final words = text.split(RegExp(r'(\s+)'));

    for (int i = 0; i < words.length; i++) {
      final word = words[i];

      if (word.startsWith('@') && word.length > 1) {
        // Mention
        spans.add(_buildMentionSpan(word));
      } else if (_isUrl(word)) {
        // URL
        spans.add(_buildUrlSpan(word));
      } else {
        // Regular text
        spans.add(TextSpan(
          text: word,
          style: TextStyle(color: textColor),
        ));
      }

      // Add space between words (except for last word)
      if (i < words.length - 1) {
        spans.add(TextSpan(
          text: ' ',
          style: TextStyle(color: textColor),
        ));
      }
    }

    return RichText(
      textWidthBasis: TextWidthBasis.longestLine,
      text: TextSpan(
        children: spans,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: textColor,
              height: 1.3,
            ),
      ),
    );
  }

  /// Build formatted text (for future rich text support)
  Widget _buildFormattedText(BuildContext context) {
    // TODO: Implement rich text formatting (bold, italic, etc.)
    return _buildPlainText(context);
  }

  /// Build mention text span
  TextSpan _buildMentionSpan(String mention) {
    return TextSpan(
      text: mention,
      style: TextStyle(
        color: isFromCurrentUser ? Colors.white : Colors.blue,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.none,
      ),
      recognizer: TapGestureRecognizer()
        ..onTap = () {
          // TODO: Handle mention tap (show user profile)
          debugPrint('Tapped mention: $mention');
        },
    );
  }

  /// Build URL text span
  TextSpan _buildUrlSpan(String url) {
    return TextSpan(
      text: url,
      style: TextStyle(
        color: isFromCurrentUser ? Colors.white : Colors.blue,
        decoration: TextDecoration.underline,
      ),
      recognizer: TapGestureRecognizer()..onTap = () => _launchUrl(url),
    );
  }

  /// Check if text is a URL
  bool _isUrl(String text) {
    final urlPattern = RegExp(
      r'^(https?:\/\/)?([\da-z\.-]+)\.([a-z\.]{2,6})([\/\w \.-]*)*\/?$',
      caseSensitive: false,
    );
    return urlPattern.hasMatch(text);
  }

  /// Launch URL
  Future<void> _launchUrl(String url) async {
    try {
      String urlToLaunch = url;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        urlToLaunch = 'https://$url';
      }

      final uri = Uri.parse(urlToLaunch);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('❌ Error launching URL: $e');
    }
  }

  /// Format message time
  String _formatMessageTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays == 0) {
      // Today - show time
      final hour = time.hour;
      final minute = time.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    } else {
      // Other days - show relative time
      return timeago.format(time, allowFromNow: true);
    }
  }
}

/// Widget for displaying code blocks (for future use)
class CodeBlockWidget extends StatelessWidget {
  final String code;
  final String? language;
  final Color textColor;

  const CodeBlockWidget({
    super.key,
    required this.code,
    this.language,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Language label
          if (language != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                language!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: textColor.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          // Code content
          SelectableText(
            code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: textColor,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget for displaying quotes (for future use)
class QuoteWidget extends StatelessWidget {
  final String quote;
  final String? author;
  final Color textColor;

  const QuoteWidget({
    super.key,
    required this.quote,
    this.author,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: textColor.withOpacity(0.5),
            width: 4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            quote,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: textColor.withOpacity(0.9),
              fontStyle: FontStyle.italic,
              height: 1.3,
            ),
          ),
          if (author != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '— $author',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: textColor.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
