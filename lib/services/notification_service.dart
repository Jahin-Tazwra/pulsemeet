import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'dart:math' as math;

/// A service to handle notifications for pulses
class NotificationService {
  // Singleton instance
  static final NotificationService _instance = NotificationService._internal();
  
  factory NotificationService() => _instance;
  
  NotificationService._internal();
  
  /// Default notification radius in meters
  static const int defaultNotificationRadius = 5000;
  
  /// Check if a user is within the notification radius of a pulse
  bool isUserWithinNotificationRadius(LatLng userLocation, Pulse pulse, {int? notificationRadius}) {
    // Use the provided notification radius or the default
    final radius = notificationRadius ?? defaultNotificationRadius;
    
    // Calculate the distance between the user and the pulse
    final distance = calculateDistance(userLocation, pulse.location);
    
    // Convert to meters
    final distanceMeters = distance * 1000;
    
    // Check if the user is within the notification radius
    return distanceMeters <= radius;
  }
  
  /// Calculate distance between two points using the Haversine formula
  double calculateDistance(LatLng point1, LatLng point2) {
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
  
  /// Show a notification for a new pulse
  void showPulseNotification(Pulse pulse) {
    // This would be implemented with a proper notification system
    // For now, we'll just log it
    debugPrint('Showing notification for pulse: ${pulse.id} - ${pulse.title}');
    
    // In a real implementation, this would use Firebase Cloud Messaging
    // or another notification service to show a push notification
  }
}
