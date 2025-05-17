import 'dart:convert';

/// Types of formatted text segments
enum FormattedSegmentType {
  text,
  mention,
  link,
}

/// A segment of formatted text
class FormattedSegment {
  final String text;
  final FormattedSegmentType type;
  final String? metadata;

  FormattedSegment({
    required this.text,
    required this.type,
    this.metadata,
  });

  /// Create a FormattedSegment from JSON
  factory FormattedSegment.fromJson(Map<String, dynamic> json) {
    return FormattedSegment(
      text: json['text'],
      type: FormattedSegmentType.values.firstWhere(
        (e) => e.toString() == 'FormattedSegmentType.${json['type']}',
        orElse: () => FormattedSegmentType.text,
      ),
      metadata: json['metadata'],
    );
  }

  /// Convert FormattedSegment to JSON
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'type': type.toString().split('.').last,
      'metadata': metadata,
    };
  }
}

/// A formatted text with segments
class FormattedText {
  final List<FormattedSegment> segments;

  FormattedText({
    required this.segments,
  });

  /// Create a FormattedText from JSON
  factory FormattedText.fromJson(Map<String, dynamic> json) {
    return FormattedText(
      segments: (json['segments'] as List)
          .map((e) => FormattedSegment.fromJson(e))
          .toList(),
    );
  }

  /// Convert FormattedText to JSON
  Map<String, dynamic> toJson() {
    return {
      'segments': segments.map((e) => e.toJson()).toList(),
    };
  }

  /// Create a FormattedText from a string
  factory FormattedText.fromString(String text) {
    // If the text is empty, return an empty FormattedText
    if (text.isEmpty) {
      return FormattedText(segments: []);
    }

    // Parse the text for mentions and links
    final List<FormattedSegment> segments = [];
    final RegExp mentionRegex = RegExp(r'@(\w+)');
    final RegExp linkRegex = RegExp(
        r'(https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9]+\.[^\s]{2,}|www\.[a-zA-Z0-9]+\.[^\s]{2,})');

    // Combine both regexes to find all special segments
    final RegExp combinedRegex = RegExp('$mentionRegex|$linkRegex');

    // Find all matches
    final matches = combinedRegex.allMatches(text);

    // If no matches, return the text as a single segment
    if (matches.isEmpty) {
      segments.add(FormattedSegment(
        text: text,
        type: FormattedSegmentType.text,
      ));
      return FormattedText(segments: segments);
    }

    // Process matches and text between matches
    int lastEnd = 0;
    for (final match in matches) {
      // Add text before match
      if (match.start > lastEnd) {
        segments.add(FormattedSegment(
          text: text.substring(lastEnd, match.start),
          type: FormattedSegmentType.text,
        ));
      }

      // Add match
      final matchText = text.substring(match.start, match.end);
      if (mentionRegex.hasMatch(matchText)) {
        segments.add(FormattedSegment(
          text: matchText,
          type: FormattedSegmentType.mention,
          metadata: matchText.substring(1), // Remove @ symbol
        ));
      } else if (linkRegex.hasMatch(matchText)) {
        segments.add(FormattedSegment(
          text: matchText,
          type: FormattedSegmentType.link,
          metadata: matchText,
        ));
      }

      lastEnd = match.end;
    }

    // Add text after last match
    if (lastEnd < text.length) {
      segments.add(FormattedSegment(
        text: text.substring(lastEnd),
        type: FormattedSegmentType.text,
      ));
    }

    return FormattedText(segments: segments);
  }

  /// Convert FormattedText to a string
  @override
  String toString() {
    return segments.map((e) => e.text).join();
  }

  /// Encode FormattedText to a string for storage
  String encode() {
    return jsonEncode(toJson());
  }

  /// Decode FormattedText from a string
  static FormattedText decode(String encoded) {
    return FormattedText.fromJson(jsonDecode(encoded));
  }
}
