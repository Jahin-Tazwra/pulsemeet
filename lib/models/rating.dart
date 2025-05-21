import 'package:flutter/foundation.dart';

/// Model class for user ratings
class Rating {
  final String id;
  final String raterId;
  final String ratedUserId;
  final String pulseId;
  final int ratingValue;
  final String? comment;
  final DateTime createdAt;
  final DateTime updatedAt;

  Rating({
    required this.id,
    required this.raterId,
    required this.ratedUserId,
    required this.pulseId,
    required this.ratingValue,
    this.comment,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a Rating from JSON data
  factory Rating.fromJson(Map<String, dynamic> json) {
    try {
      return Rating(
        id: json['id'] ?? '',
        raterId: json['rater_id'] ?? '',
        ratedUserId: json['rated_user_id'] ?? '',
        pulseId: json['pulse_id'] ?? '',
        ratingValue: json['rating_value'] ?? 0,
        comment: json['comment'],
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : DateTime.now(),
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'])
            : DateTime.now(),
      );
    } catch (e) {
      debugPrint('Error creating Rating from JSON: $e');
      rethrow;
    }
  }

  /// Convert Rating to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rater_id': raterId,
      'rated_user_id': ratedUserId,
      'pulse_id': pulseId,
      'rating_value': ratingValue,
      'comment': comment,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy of Rating with updated fields
  Rating copyWith({
    String? id,
    String? raterId,
    String? ratedUserId,
    String? pulseId,
    int? ratingValue,
    String? comment,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Rating(
      id: id ?? this.id,
      raterId: raterId ?? this.raterId,
      ratedUserId: ratedUserId ?? this.ratedUserId,
      pulseId: pulseId ?? this.pulseId,
      ratingValue: ratingValue ?? this.ratingValue,
      comment: comment ?? this.comment,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Model class for rating statistics
class RatingStats {
  final double averageRating;
  final int totalRatings;
  final Map<int, int> ratingDistribution;

  RatingStats({
    required this.averageRating,
    required this.totalRatings,
    required this.ratingDistribution,
  });

  /// Create RatingStats from a list of ratings
  factory RatingStats.fromRatings(List<Rating> ratings) {
    if (ratings.isEmpty) {
      return RatingStats(
        averageRating: 0.0,
        totalRatings: 0,
        ratingDistribution: {
          1: 0,
          2: 0,
          3: 0,
          4: 0,
          5: 0,
        },
      );
    }

    // Calculate average rating
    final sum = ratings.fold<int>(
        0, (previousValue, rating) => previousValue + rating.ratingValue);
    final average = sum / ratings.length;

    // Calculate rating distribution
    final distribution = {
      1: 0,
      2: 0,
      3: 0,
      4: 0,
      5: 0,
    };

    for (final rating in ratings) {
      distribution[rating.ratingValue] = (distribution[rating.ratingValue] ?? 0) + 1;
    }

    return RatingStats(
      averageRating: double.parse(average.toStringAsFixed(2)),
      totalRatings: ratings.length,
      ratingDistribution: distribution,
    );
  }

  /// Create RatingStats from profile data
  factory RatingStats.fromProfile(double averageRating, int totalRatings) {
    return RatingStats(
      averageRating: averageRating,
      totalRatings: totalRatings,
      ratingDistribution: {
        1: 0,
        2: 0,
        3: 0,
        4: 0,
        5: 0,
      },
    );
  }

  /// Get percentage for a specific rating value
  double getPercentage(int ratingValue) {
    if (totalRatings == 0) return 0.0;
    return (ratingDistribution[ratingValue] ?? 0) / totalRatings * 100;
  }
}
