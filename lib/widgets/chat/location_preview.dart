import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/screens/map/location_viewer_screen.dart';

/// A widget that displays a preview of a location
class LocationPreview extends StatelessWidget {
  final LatLng location;
  final String? address;
  final bool isLive;
  final DateTime? expiresAt;
  final bool isFromCurrentUser;
  final double width;
  final double height;

  const LocationPreview({
    super.key,
    required this.location,
    this.address,
    this.isLive = false,
    this.expiresAt,
    required this.isFromCurrentUser,
    this.width = 240.0,
    this.height = 160.0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openLocationViewer(context),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16.0),
            topRight: Radius.circular(16.0),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Map preview
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16.0),
                topRight: Radius.circular(16.0),
              ),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: location,
                  zoom: 15.0,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('location'),
                    position: location,
                  ),
                },
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                myLocationEnabled: false,
                compassEnabled: false,
                tiltGesturesEnabled: false,
                rotateGesturesEnabled: false,
                scrollGesturesEnabled: false,
                zoomGesturesEnabled: false,
                liteModeEnabled: true,
              ),
            ),
            
            // Address overlay
            if (address != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 8.0,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16.0),
                      bottomRight: Radius.circular(16.0),
                    ),
                  ),
                  child: Text(
                    address!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.0,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            
            // Live indicator
            if (isLive)
              Positioned(
                top: 8.0,
                right: 8.0,
                child: _buildLiveIndicator(context),
              ),
          ],
        ),
      ),
    );
  }
  
  /// Build the live indicator
  Widget _buildLiveIndicator(BuildContext context) {
    // Calculate remaining time if expiresAt is available
    String timeText = 'LIVE';
    if (expiresAt != null) {
      final now = DateTime.now();
      final remaining = expiresAt!.difference(now);
      
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
  
  /// Open the location viewer screen
  void _openLocationViewer(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationViewerScreen(
          location: location,
          address: address,
          isLive: isLive,
          expiresAt: expiresAt,
        ),
      ),
    );
  }
}
