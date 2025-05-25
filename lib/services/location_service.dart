import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pulsemeet/models/message.dart';
import 'package:uuid/uuid.dart';

/// A service for handling location-related functionality
class LocationService {
  static final LocationService _instance = LocationService._internal();

  factory LocationService() => _instance;

  LocationService._internal();

  final Uuid _uuid = const Uuid();

  // Map of active live location streams
  final Map<String, StreamSubscription<Position>> _liveLocationStreams = {};

  // Map of live location update callbacks
  final Map<String, Function(LocationData)> _liveLocationCallbacks = {};

  /// Get the current location
  Future<Position?> getCurrentLocation() async {
    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      // Get current position with high accuracy
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return null;
    }
  }

  /// Get the address from coordinates
  Future<String?> getAddressFromCoordinates(
      double latitude, double longitude) async {
    try {
      final List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );

      if (placemarks.isNotEmpty) {
        final Placemark place = placemarks.first;
        return '${place.street}, ${place.locality}, ${place.administrativeArea}';
      }

      return null;
    } catch (e) {
      debugPrint('Error getting address from coordinates: $e');
      return null;
    }
  }

  /// Create a location data object
  Future<LocationData?> createLocationData({
    bool isLive = false,
    Duration? expiresAfter,
  }) async {
    try {
      final Position? position = await getCurrentLocation();

      if (position == null) return null;

      final String? address = await getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      DateTime? expiresAt;
      if (expiresAfter != null) {
        expiresAt = DateTime.now().add(expiresAfter);
      }

      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
        liveLocationExpiresAt: expiresAt,
        isLiveLocation: isLive,
      );
    } catch (e) {
      debugPrint('Error creating location data: $e');
      return null;
    }
  }

  /// Start sharing live location
  Future<String?> startLiveLocationSharing(
    String pulseId,
    String messageId,
    Function(LocationData) onLocationUpdate,
    Duration duration,
  ) async {
    try {
      // Check if we already have a stream for this message
      if (_liveLocationStreams.containsKey(messageId)) {
        return messageId;
      }

      // Get initial location
      final Position? initialPosition = await getCurrentLocation();
      if (initialPosition == null) return null;

      // Store the callback
      _liveLocationCallbacks[messageId] = onLocationUpdate;

      // Calculate expiry time
      final expiresAt = DateTime.now().add(duration);

      // Create initial location data
      final String? address = await getAddressFromCoordinates(
        initialPosition.latitude,
        initialPosition.longitude,
      );

      final initialLocationData = LocationData(
        latitude: initialPosition.latitude,
        longitude: initialPosition.longitude,
        address: address,
        liveLocationExpiresAt: expiresAt,
        isLiveLocation: true,
      );

      // Call the callback with initial data
      onLocationUpdate(initialLocationData);

      // Start location stream
      final StreamSubscription<Position> subscription =
          Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
        ),
      ).listen((Position position) async {
        // Check if the stream should be stopped
        if (DateTime.now().isAfter(expiresAt)) {
          await stopLiveLocationSharing(messageId);
          return;
        }

        // Get address
        final String? newAddress = await getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );

        // Create location data
        final locationData = LocationData(
          latitude: position.latitude,
          longitude: position.longitude,
          address: newAddress,
          liveLocationExpiresAt: expiresAt,
          isLiveLocation: true,
        );

        // Call the callback
        if (_liveLocationCallbacks.containsKey(messageId)) {
          _liveLocationCallbacks[messageId]!(locationData);
        }
      });

      // Store the subscription
      _liveLocationStreams[messageId] = subscription;

      return messageId;
    } catch (e) {
      debugPrint('Error starting live location sharing: $e');
      return null;
    }
  }

  /// Stop sharing live location
  Future<bool> stopLiveLocationSharing(String messageId) async {
    try {
      if (_liveLocationStreams.containsKey(messageId)) {
        await _liveLocationStreams[messageId]!.cancel();
        _liveLocationStreams.remove(messageId);
        _liveLocationCallbacks.remove(messageId);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error stopping live location sharing: $e');
      return false;
    }
  }

  /// Generate a static map image for a location
  Future<File?> generateStaticMapImage(LatLng location) async {
    try {
      // Create a temporary widget with a map
      final GoogleMapController controller = await _getMapController(location);

      // Capture the map as an image
      final Uint8List? imageBytes = await controller.takeSnapshot();
      controller.dispose();

      if (imageBytes == null) return null;

      // Save the image to a temporary file
      final tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/${_uuid.v4()}.png';
      final File file = File(filePath);
      await file.writeAsBytes(imageBytes);

      return file;
    } catch (e) {
      debugPrint('Error generating static map image: $e');
      return null;
    }
  }

  /// Get a map controller for a specific location
  Future<GoogleMapController> _getMapController(LatLng location) async {
    final Completer<GoogleMapController> completer = Completer();

    // This is a hack to get a map controller without showing a map
    // In a real app, you might want to use a proper map rendering service
    // We need to create a GoogleMap widget to get a controller, but we don't actually use the widget
    GoogleMap(
      initialCameraPosition: CameraPosition(
        target: location,
        zoom: 15,
      ),
      onMapCreated: (GoogleMapController controller) {
        completer.complete(controller);
      },
    );

    // In a real implementation, we would render the map widget to an image
    // For now, we'll just create the controller
    final controller = await completer.future;

    // Wait for the map to load
    await Future.delayed(const Duration(seconds: 1));

    return controller;
  }

  /// Dispose all resources
  void dispose() {
    for (final subscription in _liveLocationStreams.values) {
      subscription.cancel();
    }
    _liveLocationStreams.clear();
    _liveLocationCallbacks.clear();
  }
}
