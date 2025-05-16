import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A simple geofence service that uses Geolocator to monitor the user's location
/// and triggers callbacks when the user enters or exits a geofence.
class GeofenceService {
  /// Singleton instance
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;
  GeofenceService._internal();

  /// Stream controller for geofence events
  final _geofenceStreamController = StreamController<GeofenceEvent>.broadcast();

  /// Stream of geofence events
  Stream<GeofenceEvent> get geofenceStream => _geofenceStreamController.stream;

  /// List of active geofences
  final List<Geofence> _geofences = [];

  /// Current position
  Position? _currentPosition;

  /// Location stream subscription
  StreamSubscription<Position>? _positionStreamSubscription;

  /// Whether the service is running
  bool _isRunning = false;

  /// Get whether the service is running
  bool get isRunning => _isRunning;

  /// Start the geofence service
  Future<bool> start() async {
    if (_isRunning) return true;

    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return false;
      }

      // Get current position
      _currentPosition = await Geolocator.getCurrentPosition();

      // Start listening to location updates
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(_onPositionUpdate);

      _isRunning = true;
      return true;
    } catch (e) {
      debugPrint('Error starting geofence service: $e');
      return false;
    }
  }

  /// Stop the geofence service
  Future<void> stop() async {
    if (!_isRunning) return;

    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _isRunning = false;
  }

  /// Add a geofence
  void addGeofence(Geofence geofence) {
    _geofences.add(geofence);
    // Check if the user is already in the geofence
    _checkGeofence(geofence);
  }

  /// Remove a geofence
  void removeGeofence(String id) {
    _geofences.removeWhere((geofence) => geofence.id == id);
  }

  /// Clear all geofences
  void clearGeofences() {
    _geofences.clear();
  }

  /// Handle position updates
  void _onPositionUpdate(Position position) {
    final previousPosition = _currentPosition;
    _currentPosition = position;

    // Check all geofences
    for (final geofence in _geofences) {
      _checkGeofence(geofence, previousPosition);
    }
  }

  /// Check if the user is inside a geofence
  void _checkGeofence(Geofence geofence, [Position? previousPosition]) {
    if (_currentPosition == null) return;

    final distance = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      geofence.center.latitude,
      geofence.center.longitude,
    );

    final isInside = distance <= geofence.radius;

    // If previous position is null, just check if we're inside
    if (previousPosition == null) {
      if (isInside) {
        _geofenceStreamController.add(
          GeofenceEvent(
            geofence: geofence,
            eventType: GeofenceEventType.enter,
            position: _currentPosition!,
          ),
        );
      }
      return;
    }

    // Calculate previous distance
    final previousDistance = Geolocator.distanceBetween(
      previousPosition.latitude,
      previousPosition.longitude,
      geofence.center.latitude,
      geofence.center.longitude,
    );

    final wasInside = previousDistance <= geofence.radius;

    // Trigger events only when crossing the boundary
    if (isInside && !wasInside) {
      // Entered the geofence
      _geofenceStreamController.add(
        GeofenceEvent(
          geofence: geofence,
          eventType: GeofenceEventType.enter,
          position: _currentPosition!,
        ),
      );
    } else if (!isInside && wasInside) {
      // Exited the geofence
      _geofenceStreamController.add(
        GeofenceEvent(
          geofence: geofence,
          eventType: GeofenceEventType.exit,
          position: _currentPosition!,
        ),
      );
    }
  }

  /// Dispose the service
  void dispose() {
    _positionStreamSubscription?.cancel();
    _geofenceStreamController.close();
  }
}

/// Geofence event type
enum GeofenceEventType {
  /// User entered the geofence
  enter,

  /// User exited the geofence
  exit,
}

/// Geofence event
class GeofenceEvent {
  /// The geofence that triggered the event
  final Geofence geofence;

  /// The type of event
  final GeofenceEventType eventType;

  /// The user's position when the event was triggered
  final Position position;

  /// Create a new geofence event
  GeofenceEvent({
    required this.geofence,
    required this.eventType,
    required this.position,
  });
}

/// Geofence
class Geofence {
  /// Unique identifier
  final String id;

  /// Center of the geofence
  final LatLng center;

  /// Radius of the geofence in meters
  final double radius;

  /// Optional data associated with the geofence
  final Map<String, dynamic>? data;

  /// Create a new geofence
  Geofence({
    required this.id,
    required this.center,
    required this.radius,
    this.data,
  });
}
