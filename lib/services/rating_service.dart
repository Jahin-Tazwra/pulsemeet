import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pulsemeet/models/rating.dart';
import 'package:pulsemeet/models/profile.dart';

/// Service for managing user ratings
class RatingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Submit a rating for a user
  Future<Rating> submitRating({
    required String ratedUserId,
    required String pulseId,
    required int ratingValue,
    String? comment,
  }) async {
    try {
      final raterId = _supabase.auth.currentUser?.id;
      if (raterId == null) {
        throw Exception('User not authenticated');
      }

      // Validate rating value
      if (ratingValue < 1 || ratingValue > 5) {
        throw Exception('Rating value must be between 1 and 5');
      }

      // Check if user has already rated this user for this pulse
      final existingRating = await _supabase
          .from('ratings')
          .select()
          .eq('rater_id', raterId)
          .eq('rated_user_id', ratedUserId)
          .eq('pulse_id', pulseId)
          .maybeSingle();

      Map<String, dynamic> ratingData = {
        'rater_id': raterId,
        'rated_user_id': ratedUserId,
        'pulse_id': pulseId,
        'rating_value': ratingValue,
        'comment': comment,
      };

      Map<String, dynamic> result;
      if (existingRating != null) {
        // Update existing rating
        result = await _supabase
            .from('ratings')
            .update(ratingData)
            .eq('id', existingRating['id'])
            .select()
            .single();
      } else {
        // Insert new rating
        result = await _supabase
            .from('ratings')
            .insert(ratingData)
            .select()
            .single();
      }

      return Rating.fromJson(result);
    } catch (e) {
      debugPrint('Error submitting rating: $e');
      rethrow;
    }
  }

  /// Get ratings for a user
  Future<List<Rating>> getRatingsForUser(String userId) async {
    try {
      final result = await _supabase
          .from('ratings')
          .select()
          .eq('rated_user_id', userId)
          .order('created_at', ascending: false);

      return result.map<Rating>((json) => Rating.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error getting ratings for user: $e');
      return [];
    }
  }

  /// Get rating statistics for a user
  Future<RatingStats> getRatingStats(String userId) async {
    try {
      // Get the user's profile to get the average rating and total ratings
      final profileResult = await _supabase
          .from('profiles')
          .select('average_rating, total_ratings')
          .eq('id', userId)
          .single();

      final double averageRating =
          double.tryParse(profileResult['average_rating'].toString()) ?? 0.0;
      final int totalRatings = profileResult['total_ratings'] ?? 0;

      // Get all ratings to calculate distribution
      final ratings = await getRatingsForUser(userId);

      return RatingStats.fromRatings(ratings);
    } catch (e) {
      debugPrint('Error getting rating stats: $e');
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
  }

  /// Check if a user can rate another user for a specific pulse
  Future<bool> canRateUser(String ratedUserId, String pulseId) async {
    try {
      final raterId = _supabase.auth.currentUser?.id;
      if (raterId == null) return false;

      // Cannot rate yourself
      if (raterId == ratedUserId) return false;

      // Check if user participated in the pulse
      final participantResult = await _supabase
          .from('pulse_participants')
          .select()
          .eq('pulse_id', pulseId)
          .eq('user_id', raterId)
          .eq('status', 'active')
          .maybeSingle();

      if (participantResult == null) return false;

      // Check if user has already rated this user for this pulse
      final existingRating = await _supabase
          .from('ratings')
          .select()
          .eq('rater_id', raterId)
          .eq('rated_user_id', ratedUserId)
          .eq('pulse_id', pulseId)
          .maybeSingle();

      // User can rate if they haven't already rated or if they want to update their rating
      return true;
    } catch (e) {
      debugPrint('Error checking if user can rate: $e');
      return false;
    }
  }

  /// Get ratings given by a user
  Future<List<Rating>> getRatingsByUser(String userId) async {
    try {
      final result = await _supabase
          .from('ratings')
          .select()
          .eq('rater_id', userId)
          .order('created_at', ascending: false);

      return result.map<Rating>((json) => Rating.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error getting ratings by user: $e');
      return [];
    }
  }

  /// Delete a rating
  Future<bool> deleteRating(String ratingId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      // Check if the rating belongs to the user
      final rating = await _supabase
          .from('ratings')
          .select()
          .eq('id', ratingId)
          .eq('rater_id', userId)
          .maybeSingle();

      if (rating == null) return false;

      // Delete the rating
      await _supabase.from('ratings').delete().eq('id', ratingId);

      return true;
    } catch (e) {
      debugPrint('Error deleting rating: $e');
      return false;
    }
  }

  /// Get a specific rating
  Future<Rating?> getRating(String ratingId) async {
    try {
      final result = await _supabase
          .from('ratings')
          .select()
          .eq('id', ratingId)
          .maybeSingle();

      if (result == null) return null;

      return Rating.fromJson(result);
    } catch (e) {
      debugPrint('Error getting rating: $e');
      return null;
    }
  }

  /// Get a rating for a specific user and pulse
  Future<Rating?> getRatingForUserAndPulse(
      String ratedUserId, String pulseId) async {
    try {
      final raterId = _supabase.auth.currentUser?.id;
      if (raterId == null) return null;

      final result = await _supabase
          .from('ratings')
          .select()
          .eq('rater_id', raterId)
          .eq('rated_user_id', ratedUserId)
          .eq('pulse_id', pulseId)
          .maybeSingle();

      if (result == null) return null;

      return Rating.fromJson(result);
    } catch (e) {
      debugPrint('Error getting rating for user and pulse: $e');
      return null;
    }
  }
}
