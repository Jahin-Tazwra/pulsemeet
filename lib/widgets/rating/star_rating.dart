import 'package:flutter/material.dart';

/// A widget that displays a star rating
class StarRating extends StatelessWidget {
  final double rating;
  final double size;
  final Color? color;
  final Color? unratedColor;
  final bool allowHalfRating;
  final bool showRatingText;
  final TextStyle? ratingTextStyle;
  final MainAxisAlignment alignment;
  final EdgeInsets padding;

  const StarRating({
    super.key,
    required this.rating,
    this.size = 24.0,
    this.color,
    this.unratedColor,
    this.allowHalfRating = true,
    this.showRatingText = false,
    this.ratingTextStyle,
    this.alignment = MainAxisAlignment.start,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final starColor = color ?? Theme.of(context).colorScheme.primary;
    final emptyColor = unratedColor ?? Colors.grey.shade300;
    final actualRating = allowHalfRating
        ? rating
        : rating.roundToDouble();
    
    return Padding(
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: alignment,
        children: [
          ...List.generate(5, (index) {
            if (index < actualRating.floor()) {
              // Full star
              return Icon(
                Icons.star,
                color: starColor,
                size: size,
              );
            } else if (index == actualRating.floor() &&
                actualRating % 1 > 0) {
              // Half star
              return Stack(
                children: [
                  Icon(
                    Icons.star,
                    color: emptyColor,
                    size: size,
                  ),
                  ClipRect(
                    clipper: _HalfClipper(),
                    child: Icon(
                      Icons.star,
                      color: starColor,
                      size: size,
                    ),
                  ),
                ],
              );
            } else {
              // Empty star
              return Icon(
                Icons.star,
                color: emptyColor,
                size: size,
              );
            }
          }),
          if (showRatingText) ...[
            const SizedBox(width: 4),
            Text(
              rating.toStringAsFixed(1),
              style: ratingTextStyle ??
                  TextStyle(
                    fontSize: size * 0.75,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A clipper that clips the right half of a widget
class _HalfClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, 0, size.width / 2, size.height);
  }

  @override
  bool shouldReclip(_HalfClipper oldClipper) => false;
}

/// A widget that allows users to select a star rating
class StarRatingSelector extends StatefulWidget {
  final int initialRating;
  final ValueChanged<int> onRatingChanged;
  final double size;
  final Color? color;
  final Color? unratedColor;
  final bool allowHalfRating;
  final bool showRatingText;
  final TextStyle? ratingTextStyle;
  final MainAxisAlignment alignment;
  final EdgeInsets padding;

  const StarRatingSelector({
    super.key,
    this.initialRating = 0,
    required this.onRatingChanged,
    this.size = 36.0,
    this.color,
    this.unratedColor,
    this.allowHalfRating = false,
    this.showRatingText = true,
    this.ratingTextStyle,
    this.alignment = MainAxisAlignment.center,
    this.padding = const EdgeInsets.symmetric(vertical: 8.0),
  });

  @override
  State<StarRatingSelector> createState() => _StarRatingSelectorState();
}

class _StarRatingSelectorState extends State<StarRatingSelector> {
  late int _rating;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
  }

  @override
  Widget build(BuildContext context) {
    final starColor = widget.color ?? Theme.of(context).colorScheme.primary;
    final emptyColor = widget.unratedColor ?? Colors.grey.shade300;

    return Padding(
      padding: widget.padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: widget.alignment,
        children: [
          ...List.generate(5, (index) {
            final starValue = index + 1;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _rating = starValue;
                });
                widget.onRatingChanged(_rating);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Icon(
                  starValue <= _rating ? Icons.star : Icons.star_border,
                  color: starValue <= _rating ? starColor : emptyColor,
                  size: widget.size,
                ),
              ),
            );
          }),
          if (widget.showRatingText && _rating > 0) ...[
            const SizedBox(width: 8),
            Text(
              '$_rating/5',
              style: widget.ratingTextStyle ??
                  TextStyle(
                    fontSize: widget.size * 0.6,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
