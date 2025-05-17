import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'package:pulsemeet/services/notification_service.dart';

/// A service to notify listeners when pulses are created or updated
class PulseNotifier {
  // Singleton instance
  static final PulseNotifier _instance = PulseNotifier._internal();

  factory PulseNotifier() => _instance;

  PulseNotifier._internal();

  // Stream controller for pulse creation events
  final _pulseCreatedController = StreamController<Pulse>.broadcast();

  // Stream controller for pulse creation events that are within notification radius
  final _pulseCreatedNearbyController = StreamController<Pulse>.broadcast();

  // Notification service
  final _notificationService = NotificationService();

  // Current user location
  LatLng? _currentUserLocation;

  /// Stream of all pulse creation events (regardless of distance)
  Stream<Pulse> get onPulseCreated => _pulseCreatedController.stream;

  /// Stream of pulse creation events that are within notification radius
  Stream<Pulse> get onPulseCreatedNearby =>
      _pulseCreatedNearbyController.stream;

  /// Update the current user location
  void updateUserLocation(LatLng location) {
    _currentUserLocation = location;
  }

  /// Update the current user location from Position
  void updateUserLocationFromPosition(Position position) {
    _currentUserLocation = LatLng(position.latitude, position.longitude);
  }

  /// Notify listeners that a pulse was created
  /// This will notify all listeners regardless of distance
  /// but will only send notifications to users within the notification radius
  void notifyPulseCreated(Pulse pulse) {
    debugPrint('PulseNotifier: Notifying pulse created: ${pulse.id}');

    // Always add to the main stream for UI updates
    _pulseCreatedController.add(pulse);

    // Check if we have the user's location
    if (_currentUserLocation != null) {
      // Check if the user is within the notification radius
      final isWithinRadius =
          _notificationService.isUserWithinNotificationRadius(
        _currentUserLocation!,
        pulse,
      );

      debugPrint(
          'PulseNotifier: User is ${isWithinRadius ? "within" : "outside"} notification radius');

      // Only notify users within the radius
      if (isWithinRadius) {
        // Add to the nearby stream for notifications
        _pulseCreatedNearbyController.add(pulse);

        // Show a notification
        _notificationService.showPulseNotification(pulse);
      }
    } else {
      debugPrint(
          'PulseNotifier: User location not available, skipping notification radius check');
    }
  }

  /// Dispose resources
  void dispose() {
    _pulseCreatedController.close();
    _pulseCreatedNearbyController.close();
  }
}
