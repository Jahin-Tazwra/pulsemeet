import 'package:flutter/material.dart';
import 'package:pulsemeet/models/rating.dart';
import 'package:pulsemeet/widgets/rating/star_rating.dart';

/// A widget that displays a breakdown of ratings
class RatingBreakdown extends StatelessWidget {
  final RatingStats ratingStats;
  final double barHeight;
  final Color? barColor;
  final Color? backgroundColor;
  final EdgeInsets padding;

  const RatingBreakdown({
    super.key,
    required this.ratingStats,
    this.barHeight = 8.0,
    this.barColor,
    this.backgroundColor,
    this.padding = const EdgeInsets.symmetric(vertical: 16.0),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actualBarColor = barColor ?? theme.colorScheme.primary;
    final actualBackgroundColor =
        backgroundColor ?? theme.colorScheme.surfaceVariant;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Rating Breakdown',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              StarRating(
                rating: ratingStats.averageRating,
                size: 16,
                showRatingText: true,
                ratingTextStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${ratingStats.totalRatings})',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(5, (index) {
            final ratingValue = 5 - index;
            final percentage = ratingStats.getPercentage(ratingValue);
            final count =
                ratingStats.ratingDistribution[ratingValue] ?? 0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '$ratingValue',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(barHeight / 2),
                      child: Stack(
                        children: [
                          Container(
                            height: barHeight,
                            color: actualBackgroundColor,
                          ),
                          FractionallySizedBox(
                            widthFactor: percentage / 100,
                            child: Container(
                              height: barHeight,
                              color: actualBarColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '$count',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
