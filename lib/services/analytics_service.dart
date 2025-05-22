import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pulsemeet/config/supabase_config.dart';

/// Service for tracking analytics events
class AnalyticsService {
  final SupabaseClient _client = SupabaseConfig.client;

  /// Track a pulse share event
  Future<void> trackPulseShare(String pulseId, String shareCode) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      await _client.from('pulse_share_events').insert({
        'pulse_id': pulseId,
        'share_code': shareCode,
        'user_id': userId,
        'event_type': 'share',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error tracking pulse share: $e');
    }
  }

  /// Track a pulse view from shared link
  Future<void> trackPulseViewFromShare(String pulseId, String shareCode) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      await _client.from('pulse_share_events').insert({
        'pulse_id': pulseId,
        'share_code': shareCode,
        'user_id': userId,
        'event_type': 'view',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error tracking pulse view: $e');
    }
  }

  /// Track an app install from shared link
  Future<void> trackAppInstallFromShare(String shareCode) async {
    try {
      await _client.from('pulse_share_events').insert({
        'share_code': shareCode,
        'event_type': 'install',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error tracking app install: $e');
    }
  }

  /// Get analytics for a pulse
  Future<Map<String, dynamic>> getPulseAnalytics(String pulseId) async {
    try {
      final response = await _client.rpc(
        'get_pulse_share_analytics',
        params: {
          'pulse_id_param': pulseId,
        },
      );

      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error getting pulse analytics: $e');
      return {
        'shares': 0,
        'views': 0,
        'installs': 0,
      };
    }
  }
}
