import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'package:pulsemeet/screens/pulse/pulse_details_screen.dart';
import 'package:pulsemeet/widgets/pulse_marker.dart';

/// Widget that displays nearby pulses on a Google Map
class NearbyPulsesMapView extends StatefulWidget {
  final List<Pulse> pulses;
  final LatLng? currentLocation;
  final VoidCallback onRefresh;
  final int searchRadius;

  final Function(bool isLoading)? onFindClosestPulse;

  const NearbyPulsesMapView({
    super.key,
    required this.pulses,
    this.currentLocation,
    required this.onRefresh,
    this.searchRadius = 5000,
    this.onFindClosestPulse,
  });

  @override
  State<NearbyPulsesMapView> createState() => _NearbyPulsesMapViewState();
}

class _NearbyPulsesMapViewState extends State<NearbyPulsesMapView> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  bool _initialCameraPositionSet = false;

  @override
  void initState() {
    super.initState();
    _updateMapElements();
  }

  @override
  void didUpdateWidget(NearbyPulsesMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if current location became available
    final locationBecameAvailable =
        oldWidget.currentLocation == null && widget.currentLocation != null;

    // Check if location changed significantly
    final locationChanged =
        oldWidget.currentLocation != widget.currentLocation &&
            widget.currentLocation != null;

    // Update map elements if pulses or location changed
    if (widget.pulses != oldWidget.pulses || locationChanged) {
      _updateMapElements();
    }

    // Move camera to user location if it just became available
    if (locationBecameAvailable && _mapController != null) {
      _animateToUserLocation();
    }
  }

  void _updateMapElements() async {
    // Create markers for each pulse
    final markers = <Marker>{};
    final circles = <Circle>{};

    // Add marker for current user location if available
    if (widget.currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: widget.currentLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );

      // Add circle for search radius
      circles.add(
        Circle(
          circleId: const CircleId('search_radius'),
          center: widget.currentLocation!,
          radius: widget.searchRadius.toDouble(),
          fillColor: Colors.blue.withAlpha(25), // Light blue with low opacity
          strokeColor: Colors.blue,
          strokeWidth: 1,
        ),
      );
    }

    // Create custom markers for each pulse
    try {
      final customMarkers = await PulseMarker.createMarkersFromPulses(
        context,
        widget.pulses,
        _navigateToPulseDetails,
      );

      markers.addAll(customMarkers);

      // Add circles for each pulse radius
      for (final pulse in widget.pulses) {
        circles.add(
          Circle(
            circleId: CircleId('pulse_radius_${pulse.id}'),
            center: pulse.location,
            radius: pulse.radius.toDouble(),
            fillColor:
                Colors.orange.withAlpha(25), // Light orange with low opacity
            strokeColor: Colors.orange,
            strokeWidth: 1,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error creating custom markers: $e');

      // Fallback to default markers if custom markers fail
      for (final pulse in widget.pulses) {
        markers.add(
          Marker(
            markerId: MarkerId('pulse_${pulse.id}'),
            position: pulse.location,
            infoWindow: InfoWindow(
              title: pulse.title,
              snippet: pulse.formattedDistance,
              onTap: () => _navigateToPulseDetails(pulse),
            ),
            onTap: () {
              // Show info window when marker is tapped
              _mapController
                  ?.showMarkerInfoWindow(MarkerId('pulse_${pulse.id}'));
            },
          ),
        );

        // Add circle for pulse radius
        circles.add(
          Circle(
            circleId: CircleId('pulse_radius_${pulse.id}'),
            center: pulse.location,
            radius: pulse.radius.toDouble(),
            fillColor:
                Colors.orange.withAlpha(25), // Light orange with low opacity
            strokeColor: Colors.orange,
            strokeWidth: 1,
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _markers = markers;
        _circles = circles;
      });
    }
  }

  void _navigateToPulseDetails(Pulse pulse) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PulseDetailsScreen(pulse: pulse),
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;

    // Update map elements when map is created
    _updateMapElements();

    // If current location is already available, animate to it immediately
    if (widget.currentLocation != null) {
      // Use a small delay to ensure the map is fully loaded
      Future.delayed(const Duration(milliseconds: 100), () {
        _animateToUserLocation();
      });
    }
  }

  /// Animate the camera to the user's current location
  void _animateToUserLocation() {
    if (_mapController == null || widget.currentLocation == null) return;

    // Calculate appropriate zoom level
    final zoomLevel = _calculateZoomLevel(widget.searchRadius);

    // Animate to the user's location
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: widget.currentLocation!,
          zoom: zoomLevel,
        ),
      ),
    );

    // Mark that we've set the initial camera position
    _initialCameraPositionSet = true;
  }

  /// Find the closest pulse to the user's current location and animate to it
  void findClosestPulse() {
    if (widget.currentLocation == null || widget.pulses.isEmpty) {
      // If there's no current location or no pulses, we can't find the closest one
      return;
    }

    // Notify parent that we're starting the search
    widget.onFindClosestPulse?.call(true);

    // Find the closest pulse by calculating distance to each pulse
    Pulse? closestPulse;
    double closestDistance = double.infinity;

    for (final pulse in widget.pulses) {
      final distance = _calculateDistance(
        widget.currentLocation!,
        pulse.location,
      );

      if (distance < closestDistance) {
        closestDistance = distance;
        closestPulse = pulse;
      }
    }

    // If we found a closest pulse, animate to it
    if (closestPulse != null) {
      _animateToClosestPulse(closestPulse);
    } else {
      // Notify parent that we're done with the search
      widget.onFindClosestPulse?.call(false);
    }
  }

  /// Animate the camera to the closest pulse
  void _animateToClosestPulse(Pulse pulse) {
    if (_mapController == null) return;

    // Animate to the pulse location
    _mapController!
        .animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: pulse.location,
          zoom: 15.0, // Zoom in closer to see the pulse clearly
        ),
      ),
    )
        .then((_) {
      // After animation completes, show the info window for this pulse
      final markerId = MarkerId('pulse_${pulse.id}');
      _mapController!.showMarkerInfoWindow(markerId);

      // Notify parent that we're done with the search
      widget.onFindClosestPulse?.call(false);
    });
  }

  /// Calculate distance between two points using the Haversine formula
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371.0; // Earth's radius in kilometers

    // Convert latitude and longitude from degrees to radians
    final double lat1 = _degreesToRadians(point1.latitude);
    final double lon1 = _degreesToRadians(point1.longitude);
    final double lat2 = _degreesToRadians(point2.latitude);
    final double lon2 = _degreesToRadians(point2.longitude);

    // Haversine formula
    final double dLat = lat2 - lat1;
    final double dLon = lon2 - lon1;
    final double a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final double distance = earthRadius * c;

    return distance;
  }

  /// Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }

  // Calculate appropriate zoom level based on search radius
  double _calculateZoomLevel(int radiusInMeters) {
    // These values are approximate and may need adjustment
    if (radiusInMeters <= 500) return 16.0; // Very close
    if (radiusInMeters <= 1000) return 15.0; // 1km
    if (radiusInMeters <= 2000) return 14.0; // 2km
    if (radiusInMeters <= 5000) return 13.0; // 5km
    if (radiusInMeters <= 10000) return 12.0; // 10km
    if (radiusInMeters <= 20000) return 11.0; // 20km
    return 10.0; // Default for larger areas
  }

  @override
  Widget build(BuildContext context) {
    // Calculate zoom level based on search radius
    final zoomLevel = _calculateZoomLevel(widget.searchRadius);

    // Default to a central location if no current location is available
    // Using San Francisco as a default instead of (0,0) which is in the ocean
    final initialCameraPosition = CameraPosition(
      target: widget.currentLocation ?? const LatLng(37.7749, -122.4194),
      zoom: zoomLevel,
    );

    // Add a circle for the search radius if we have a current location
    if (widget.currentLocation != null && _circles.isNotEmpty) {
      // Update the current location range circle to match the search radius
      final searchRadiusCircle = Circle(
        circleId: const CircleId('search_radius'),
        center: widget.currentLocation!,
        radius: widget.searchRadius.toDouble(),
        fillColor:
            Colors.blue.withAlpha(20), // Very light blue with low opacity
        strokeColor: Colors.blue,
        strokeWidth: 1,
      );

      // Replace the existing circle or add a new one
      _circles = {
        ..._circles.where(
            (circle) => circle.circleId.value != 'current_location_range'),
        searchRadiusCircle,
      };
    }

    return Stack(
      children: [
        // Google Map
        GoogleMap(
          initialCameraPosition: initialCameraPosition,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          markers: _markers,
          circles: _circles,
          onMapCreated: _onMapCreated,
        ),

        // Loading indicator when waiting for location
        if (widget.currentLocation == null && !_initialCameraPositionSet)
          Container(
            color: Colors.black.withAlpha(50), // Semi-transparent overlay
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Getting your location...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          offset: Offset(1, 1),
                          blurRadius: 3,
                          color: Colors.black,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Refresh button (top right)
        Positioned(
          top: 16,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: 'refresh_map',
            onPressed: widget.onRefresh,
            child: const Icon(Icons.refresh),
          ),
        ),

        // Find Closest Pulse button (bottom center)
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              child: ElevatedButton.icon(
                onPressed: widget.pulses.isEmpty ? null : findClosestPulse,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 4,
                ),
                icon: const Icon(Icons.near_me),
                label: const Text(
                  'Find Closest Pulse',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
