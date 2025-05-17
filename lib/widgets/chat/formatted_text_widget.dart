import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pulsemeet/models/formatted_text.dart';

/// A widget to display formatted text with mentions, links, etc.
class FormattedTextWidget extends StatelessWidget {
  final FormattedText formattedText;
  final TextStyle? style;
  final TextAlign textAlign;
  final Function(String)? onMentionTap;

  const FormattedTextWidget({
    super.key,
    required this.formattedText,
    this.style,
    this.textAlign = TextAlign.left,
    this.onMentionTap,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = style ?? const TextStyle(fontSize: 16.0);
    final spans = <InlineSpan>[];

    for (final segment in formattedText.segments) {
      if (segment.type == FormattedSegmentType.mention) {
        // Mention segment
        spans.add(
          TextSpan(
            text: segment.text,
            style: defaultStyle.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                if (onMentionTap != null) {
                  // Extract username from @username
                  final username = segment.text.startsWith('@')
                      ? segment.text.substring(1)
                      : segment.text;
                  onMentionTap!(username);
                }
              },
          ),
        );
      } else if (segment.type == FormattedSegmentType.link) {
        // Link segment
        spans.add(
          TextSpan(
            text: segment.text,
            style: defaultStyle.copyWith(
              color: Colors.blue,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                // Handle link tap
                // This could open a browser or in-app webview
              },
          ),
        );
      } else {
        // Regular text segment
        spans.add(
          TextSpan(
            text: segment.text,
            style: defaultStyle,
          ),
        );
      }
    }

    return RichText(
      text: TextSpan(
        children: spans,
      ),
      textAlign: textAlign,
    );
  }
}
