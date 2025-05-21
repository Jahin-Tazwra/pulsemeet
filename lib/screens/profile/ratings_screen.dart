import 'package:flutter/material.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/models/rating.dart';
import 'package:pulsemeet/services/rating_service.dart';
import 'package:pulsemeet/widgets/rating/rating_breakdown.dart';
import 'package:pulsemeet/widgets/rating/rating_list.dart';
import 'package:pulsemeet/widgets/rating/star_rating.dart';

/// Screen to display all ratings for a user
class RatingsScreen extends StatefulWidget {
  final Profile profile;

  const RatingsScreen({
    super.key,
    required this.profile,
  });

  @override
  State<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  final _ratingService = RatingService();
  bool _isLoading = true;
  List<Rating> _ratings = [];
  RatingStats? _ratingStats;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRatings();
  }

  Future<void> _loadRatings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final ratings = await _ratingService.getRatingsForUser(widget.profile.id);
      final ratingStats = await _ratingService.getRatingStats(widget.profile.id);

      if (mounted) {
        setState(() {
          _ratings = ratings;
          _ratingStats = ratingStats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading ratings: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.profile.displayName ?? 'User'} Ratings'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadRatings,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRatings,
      child: CustomScrollView(
        slivers: [
          // Rating summary
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      StarRating(
                        rating: widget.profile.averageRating,
                        size: 32,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.profile.averageRating.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Based on ${widget.profile.totalRatings} ${widget.profile.totalRatings == 1 ? 'rating' : 'ratings'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),

          // Rating breakdown
          if (_ratingStats != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: RatingBreakdown(
                  ratingStats: _ratingStats!,
                  barHeight: 8.0,
                  barColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                ),
              ),
            ),

          // Divider
          const SliverToBoxAdapter(
            child: Divider(
              height: 32,
              indent: 16,
              endIndent: 16,
            ),
          ),

          // Ratings list header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'All Ratings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),

          // Ratings list
          _ratings.isEmpty
              ? const SliverFillRemaining(
                  child: Center(
                    child: Text('No ratings yet'),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return RatingListItem(
                        rating: _ratings[index],
                        showRatedUser: false,
                        showRater: true,
                      );
                    },
                    childCount: _ratings.length,
                  ),
                ),
        ],
      ),
    );
  }
}
