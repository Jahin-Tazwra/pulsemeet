import 'package:flutter/material.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/rating_service.dart';
import 'package:pulsemeet/widgets/avatar.dart';
import 'package:pulsemeet/widgets/rating/star_rating.dart';

/// A dialog for rating a user
class RatingDialog extends StatefulWidget {
  final Profile userToRate;
  final String pulseId;
  final VoidCallback? onRatingSubmitted;

  const RatingDialog({
    super.key,
    required this.userToRate,
    required this.pulseId,
    this.onRatingSubmitted,
  });

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  final _ratingService = RatingService();
  final _commentController = TextEditingController();
  int _rating = 0;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (_rating == 0) {
      setState(() {
        _errorMessage = 'Please select a rating';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await _ratingService.submitRating(
        ratedUserId: widget.userToRate.id,
        pulseId: widget.pulseId,
        ratingValue: _rating,
        comment: _commentController.text.trim().isNotEmpty
            ? _commentController.text.trim()
            : null,
      );

      if (mounted) {
        widget.onRatingSubmitted?.call();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Failed to submit rating: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = widget.userToRate.displayName ??
        widget.userToRate.username ??
        'Unknown User';

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Rate Your Experience',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                UserAvatar(
                  userId: widget.userToRate.id,
                  avatarUrl: widget.userToRate.avatarUrl,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.userToRate.username != null)
                        Text(
                          '@${widget.userToRate.username}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'How would you rate your experience with $displayName?',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            StarRatingSelector(
              initialRating: _rating,
              onRatingChanged: (rating) {
                setState(() {
                  _rating = rating;
                  _errorMessage = null;
                });
              },
              size: 40,
              color: theme.colorScheme.primary,
              showRatingText: true,
              alignment: MainAxisAlignment.center,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              decoration: InputDecoration(
                hintText: 'Add a comment (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () {
                          Navigator.of(context).pop(false);
                        },
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitRating,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Submit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a rating dialog for a user
Future<bool?> showRatingDialog(
  BuildContext context, {
  required Profile userToRate,
  required String pulseId,
  VoidCallback? onRatingSubmitted,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => RatingDialog(
      userToRate: userToRate,
      pulseId: pulseId,
      onRatingSubmitted: onRatingSubmitted,
    ),
  );
}
