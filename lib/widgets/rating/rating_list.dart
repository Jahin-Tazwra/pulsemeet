import 'package:flutter/material.dart';
import 'package:pulsemeet/models/rating.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/profile_service.dart';
import 'package:pulsemeet/widgets/avatar.dart';
import 'package:pulsemeet/widgets/rating/star_rating.dart';
import 'package:timeago/timeago.dart' as timeago;

/// A widget that displays a list of ratings
class RatingList extends StatelessWidget {
  final List<Rating> ratings;
  final bool showRatedUser;
  final bool showRater;
  final EdgeInsets padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  const RatingList({
    super.key,
    required this.ratings,
    this.showRatedUser = false,
    this.showRater = true,
    this.padding = EdgeInsets.zero,
    this.physics,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    if (ratings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'No ratings yet',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: padding,
      physics: physics,
      shrinkWrap: shrinkWrap,
      itemCount: ratings.length,
      itemBuilder: (context, index) {
        final rating = ratings[index];
        return RatingListItem(
          rating: rating,
          showRatedUser: showRatedUser,
          showRater: showRater,
        );
      },
    );
  }
}

/// A widget that displays a single rating
class RatingListItem extends StatefulWidget {
  final Rating rating;
  final bool showRatedUser;
  final bool showRater;

  const RatingListItem({
    super.key,
    required this.rating,
    this.showRatedUser = false,
    this.showRater = true,
  });

  @override
  State<RatingListItem> createState() => _RatingListItemState();
}

class _RatingListItemState extends State<RatingListItem> {
  final _profileService = ProfileService();
  Profile? _raterProfile;
  Profile? _ratedUserProfile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.showRater) {
        _raterProfile = await _profileService.getProfile(widget.rating.raterId);
      }

      if (widget.showRatedUser) {
        _ratedUserProfile =
            await _profileService.getProfile(widget.rating.ratedUserId);
      }
    } catch (e) {
      debugPrint('Error loading profiles: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Card(
        margin: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final raterName = _raterProfile?.displayName ??
        _raterProfile?.username ??
        'Unknown User';
    final ratedUserName = _ratedUserProfile?.displayName ??
        _ratedUserProfile?.username ??
        'Unknown User';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.showRater) ...[
                  UserAvatar(
                    userId: widget.rating.raterId,
                    avatarUrl: _raterProfile?.avatarUrl,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          raterName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'rated ${widget.showRatedUser ? ratedUserName : ''}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (widget.showRatedUser) ...[
                  UserAvatar(
                    userId: widget.rating.ratedUserId,
                    avatarUrl: _ratedUserProfile?.avatarUrl,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ratedUserName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'was rated',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StarRating(
                      rating: widget.rating.ratingValue.toDouble(),
                      size: 20,
                      allowHalfRating: false,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeago.format(widget.rating.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (widget.rating.comment != null &&
                widget.rating.comment!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.rating.comment!,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
