import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// A screen for viewing a location on a map
class LocationViewerScreen extends StatefulWidget {
  final LatLng location;
  final String? address;
  final bool isLive;
  final DateTime? expiresAt;

  const LocationViewerScreen({
    super.key,
    required this.location,
    this.address,
    this.isLive = false,
    this.expiresAt,
  });

  @override
  State<LocationViewerScreen> createState() => _LocationViewerScreenState();
}

class _LocationViewerScreenState extends State<LocationViewerScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  
  @override
  void initState() {
    super.initState();
    _updateMarkers();
  }
  
  /// Update the markers on the map
  void _updateMarkers() {
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('location'),
          position: widget.location,
          infoWindow: InfoWindow(
            title: widget.address ?? 'Location',
          ),
        ),
      };
    });
  }
  
  /// Open the location in Google Maps
  Future<void> _openInGoogleMaps() async {
    final url = 'https://www.google.com/maps/search/?api=1&query=${widget.location.latitude},${widget.location.longitude}';
    
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Google Maps'),
          ),
        );
      }
    }
  }
  
  /// Get directions to the location
  Future<void> _getDirections() async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=${widget.location.latitude},${widget.location.longitude}';
    
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Google Maps'),
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // Check if live location has expired
    bool isLive = widget.isLive;
    if (isLive && widget.expiresAt != null) {
      isLive = DateTime.now().isBefore(widget.expiresAt!);
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location'),
        actions: [
          if (isLive)
            _buildLiveIndicator(),
        ],
      ),
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.location,
              zoom: 15.0,
            ),
            markers: _markers,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapToolbarEnabled: false,
            zoomControlsEnabled: true,
          ),
          
          // Address card
          if (widget.address != null)
            Positioned(
              top: 16.0,
              left: 16.0,
              right: 16.0,
              child: Card(
                elevation: 4.0,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Address',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16.0,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Text(widget.address!),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.map),
              label: const Text('Open in Maps'),
              onPressed: _openInGoogleMaps,
            ),
            TextButton.icon(
              icon: const Icon(Icons.directions),
              label: const Text('Get Directions'),
              onPressed: _getDirections,
            ),
          ],
        ),
      ),
    );
  }
  
  /// Build the live indicator
  Widget _buildLiveIndicator() {
    // Calculate remaining time if expiresAt is available
    String timeText = 'LIVE';
    if (widget.expiresAt != null) {
      final now = DateTime.now();
      final remaining = widget.expiresAt!.difference(now);
      
      if (remaining.isNegative) {
        return const SizedBox.shrink();
      }
      
      if (remaining.inHours > 0) {
        timeText = '${remaining.inHours}h ${remaining.inMinutes % 60}m';
      } else if (remaining.inMinutes > 0) {
        timeText = '${remaining.inMinutes}m ${remaining.inSeconds % 60}s';
      } else {
        timeText = '${remaining.inSeconds}s';
      }
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(
        vertical: 12.0,
        horizontal: 16.0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 8.0,
        vertical: 4.0,
      ),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8.0,
            height: 8.0,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4.0),
            ),
          ),
          const SizedBox(width: 4.0),
          Text(
            timeText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.0,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
