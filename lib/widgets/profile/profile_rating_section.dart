import 'package:flutter/material.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/models/rating.dart';
import 'package:pulsemeet/services/rating_service.dart';
import 'package:pulsemeet/widgets/rating/star_rating.dart';
import 'package:pulsemeet/widgets/rating/rating_breakdown.dart';
import 'package:pulsemeet/widgets/rating/rating_list.dart';

/// A widget that displays a user's rating information
class ProfileRatingSection extends StatefulWidget {
  final Profile profile;
  final bool showDetailedBreakdown;
  final bool showRatings;
  final int maxRatingsToShow;
  final VoidCallback? onViewAllTap;

  const ProfileRatingSection({
    super.key,
    required this.profile,
    this.showDetailedBreakdown = true,
    this.showRatings = true,
    this.maxRatingsToShow = 3,
    this.onViewAllTap,
  });

  @override
  State<ProfileRatingSection> createState() => _ProfileRatingSectionState();
}

class _ProfileRatingSectionState extends State<ProfileRatingSection> {
  final _ratingService = RatingService();
  bool _isLoading = true;
  RatingStats? _ratingStats;
  List<Rating> _ratings = [];

  @override
  void initState() {
    super.initState();
    _loadRatingData();
  }

  @override
  void didUpdateWidget(ProfileRatingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id ||
        oldWidget.profile.totalRatings != widget.profile.totalRatings) {
      _loadRatingData();
    }
  }

  Future<void> _loadRatingData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get rating stats
      final ratingStats =
          await _ratingService.getRatingStats(widget.profile.id);

      // Get ratings if needed
      List<Rating> ratings = [];
      if (widget.showRatings) {
        ratings = await _ratingService.getRatingsForUser(widget.profile.id);
      }

      if (mounted) {
        setState(() {
          _ratingStats = ratingStats;
          _ratings = ratings;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading rating data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ratings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (!_isLoading && widget.profile.totalRatings > 0)
                  StarRating(
                    rating: widget.profile.averageRating,
                    size: 20,
                    showRatingText: true,
                    ratingTextStyle:
                        Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                  ),
              ],
            ),
          ),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (widget.profile.totalRatings == 0)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'No ratings yet',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rating summary
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      StarRating(
                        rating: widget.profile.averageRating,
                        size: 24,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.profile.averageRating.toStringAsFixed(1)} out of 5',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 4.0),
                  child: Text(
                    'Based on ${widget.profile.totalRatings} ${widget.profile.totalRatings == 1 ? 'rating' : 'ratings'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),

                // Rating breakdown
                if (widget.showDetailedBreakdown && _ratingStats != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: RatingBreakdown(
                      ratingStats: _ratingStats!,
                      barHeight: 6.0,
                      barColor: Theme.of(context).colorScheme.primary,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),

                // Recent ratings
                if (widget.showRatings && _ratings.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent Ratings',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        if (_ratings.length > widget.maxRatingsToShow)
                          TextButton(
                            onPressed: widget.onViewAllTap,
                            child: const Text('View All'),
                          ),
                      ],
                    ),
                  ),

                  // Show a limited number of ratings
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _ratings.length > widget.maxRatingsToShow
                        ? widget.maxRatingsToShow
                        : _ratings.length,
                    itemBuilder: (context, index) {
                      return RatingListItem(
                        rating: _ratings[index],
                        showRatedUser: false,
                        showRater: true,
                      );
                    },
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
