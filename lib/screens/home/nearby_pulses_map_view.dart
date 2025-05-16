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

  const NearbyPulsesMapView({
    super.key,
    required this.pulses,
    this.currentLocation,
    required this.onRefresh,
  });

  @override
  State<NearbyPulsesMapView> createState() => _NearbyPulsesMapViewState();
}

class _NearbyPulsesMapViewState extends State<NearbyPulsesMapView> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _updateMapElements();
  }

  @override
  void didUpdateWidget(NearbyPulsesMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulses != oldWidget.pulses ||
        widget.currentLocation != oldWidget.currentLocation) {
      _updateMapElements();
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

      // Add circle for current location range
      circles.add(
        Circle(
          circleId: const CircleId('current_location_range'),
          center: widget.currentLocation!,
          radius: 1000, // 1km radius
          fillColor: Colors.blue.withAlpha(25), // 0.1 opacity
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
            fillColor: Colors.orange.withAlpha(25), // 0.1 opacity
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
            fillColor: Colors.orange.withAlpha(25), // 0.1 opacity
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
  }

  @override
  Widget build(BuildContext context) {
    // Default to a central location if no current location is available
    final initialCameraPosition = CameraPosition(
      target: widget.currentLocation ?? const LatLng(0, 0),
      zoom: 14,
    );

    return Stack(
      children: [
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
        // Refresh button
        Positioned(
          top: 16,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: 'refresh_map',
            onPressed: widget.onRefresh,
            child: const Icon(Icons.refresh),
          ),
        ),
      ],
    );
  }
}
