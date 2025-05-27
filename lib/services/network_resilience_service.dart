import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for handling network resilience and retry logic
class NetworkResilienceService {
  static final NetworkResilienceService _instance =
      NetworkResilienceService._internal();
  factory NetworkResilienceService() => _instance;
  NetworkResilienceService._internal();

  final Connectivity _connectivity = Connectivity();
  bool _isOnline = true;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // Retry configuration
  static const int _maxRetries = 3;
  static const Duration _baseDelay = Duration(milliseconds: 500);
  static const Duration _maxDelay = Duration(seconds: 5);

  /// Initialize the network resilience service
  Future<void> initialize() async {
    // Check initial connectivity
    final connectivityResult = await _connectivity.checkConnectivity();
    _isOnline = connectivityResult != ConnectivityResult.none;

    // Listen for connectivity changes
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = result != ConnectivityResult.none;

      debugPrint(
          '📶 Network connectivity changed: ${_isOnline ? 'Online' : 'Offline'}');

      if (!wasOnline && _isOnline) {
        debugPrint('🔄 Network restored, reconnecting services...');
        _onNetworkRestored();
      }
    });

    debugPrint('🌐 Network resilience service initialized');
  }

  /// Check if device is currently online
  bool get isOnline => _isOnline;

  /// Execute a network operation with retry logic
  Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    String? operationName,
    int maxRetries = _maxRetries,
  }) async {
    int attempt = 0;
    Duration delay = _baseDelay;

    while (attempt < maxRetries) {
      try {
        debugPrint(
            '🔄 Executing ${operationName ?? 'operation'} (attempt ${attempt + 1}/$maxRetries)');

        // Check connectivity before attempting
        if (!_isOnline) {
          throw const SocketException('Device is offline');
        }

        final result = await operation();

        if (attempt > 0) {
          debugPrint(
              '✅ ${operationName ?? 'Operation'} succeeded after ${attempt + 1} attempts');
        }

        return result;
      } catch (e) {
        attempt++;

        if (_isNetworkError(e) && attempt < maxRetries) {
          debugPrint(
              '❌ ${operationName ?? 'Operation'} failed (attempt $attempt): $e');
          debugPrint('⏳ Retrying in ${delay.inMilliseconds}ms...');

          await Future.delayed(delay);
          delay = Duration(
              milliseconds:
                  min(delay.inMilliseconds * 2, _maxDelay.inMilliseconds));
        } else {
          debugPrint(
              '❌ ${operationName ?? 'Operation'} failed permanently: $e');
          rethrow;
        }
      }
    }

    throw Exception('Operation failed after $maxRetries attempts');
  }

  /// Execute a Supabase query with retry logic
  Future<T> executeSupabaseQuery<T>(
    Future<T> Function() query, {
    String? queryName,
  }) async {
    return executeWithRetry(
      query,
      operationName: queryName ?? 'Supabase query',
    );
  }

  /// Check if an error is network-related
  bool _isNetworkError(dynamic error) {
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;
    if (error is HttpException) return true;

    // Check for Supabase-specific network errors
    if (error is PostgrestException) {
      // Connection-related PostgrestException codes
      return error.code == 'PGRST301' || // Connection error
          error.code == 'PGRST302' || // Timeout
          error.message.toLowerCase().contains('connection') ||
          error.message.toLowerCase().contains('timeout') ||
          error.message.toLowerCase().contains('network');
    }

    // Check error message for network-related keywords
    final errorString = error.toString().toLowerCase();
    return errorString.contains('connection') ||
        errorString.contains('network') ||
        errorString.contains('timeout') ||
        errorString.contains('dns') ||
        errorString.contains('host lookup') ||
        errorString.contains('socket');
  }

  /// Handle network restoration
  void _onNetworkRestored() {
    // Notify other services that network is restored
    debugPrint('🔄 Network restored - triggering service reconnections');

    // Trigger offline queue processing if available
    _notifyNetworkRestored();
  }

  /// Notify listeners about network restoration
  void _notifyNetworkRestored() {
    // This will be used by ConversationService to process offline queue
    // Implementation can be expanded with proper event system if needed
  }

  /// Test network connectivity to Supabase
  Future<bool> testSupabaseConnectivity() async {
    try {
      final client = Supabase.instance.client;

      // Simple health check query
      await client.from('profiles').select('id').limit(1).timeout(
            const Duration(seconds: 5),
          );

      debugPrint('✅ Supabase connectivity test passed');
      return true;
    } catch (e) {
      debugPrint('❌ Supabase connectivity test failed: $e');
      return false;
    }
  }

  /// Get network status information
  Map<String, dynamic> getNetworkStatus() {
    return {
      'isOnline': _isOnline,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Dispose the service
  void dispose() {
    _connectivitySubscription?.cancel();
    debugPrint('🧹 Network resilience service disposed');
  }
}
