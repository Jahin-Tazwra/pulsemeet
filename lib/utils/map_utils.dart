import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Utility class for map-related functions
class MapUtils {
  /// Opens Google Maps with directions from current location to destination
  ///
  /// Returns true if the map was successfully opened, false otherwise
  static Future<bool> openGoogleMapsDirections(
    LatLng destination, {
    String? destinationName,
  }) async {
    try {
      // Format the destination coordinates
      final destinationStr = '${destination.latitude},${destination.longitude}';

      // Create the URL for Google Maps directions
      // We'll use different URL formats for different platforms
      String url;

      if (Platform.isAndroid) {
        // Android: Use the Google Maps app with the "google.navigation" intent
        url = 'google.navigation:q=$destinationStr&mode=d';

        // Try to launch the Google Maps app
        if (await canLaunchUrl(Uri.parse(url))) {
          return await launchUrl(Uri.parse(url));
        }

        // Fallback to the web URL if the app isn't installed
        url =
            'https://www.google.com/maps/dir/?api=1&destination=$destinationStr';
        if (destinationName != null) {
          url += '&destination_place_id=$destinationName';
        }
      } else if (Platform.isIOS) {
        // iOS: Use the Apple Maps URL scheme first
        url = 'https://maps.apple.com/?daddr=$destinationStr&dirflg=d';

        // Try to launch Apple Maps
        if (await canLaunchUrl(Uri.parse(url))) {
          return await launchUrl(Uri.parse(url));
        }

        // Fallback to Google Maps web URL
        url =
            'https://www.google.com/maps/dir/?api=1&destination=$destinationStr';
        if (destinationName != null) {
          url += '&destination_place_id=$destinationName';
        }
      } else {
        // Web or other platforms: Use the Google Maps web URL
        url =
            'https://www.google.com/maps/dir/?api=1&destination=$destinationStr';
        if (destinationName != null) {
          url += '&destination_place_id=$destinationName';
        }
      }

      // Launch the URL
      debugPrint('Opening maps URL: $url');
      return await launchUrl(Uri.parse(url));
    } catch (e) {
      debugPrint('Error opening Google Maps: $e');
      return false;
    }
  }
}
