import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/models/pulse.dart';

/// Widget for creating custom pulse markers on the map
class PulseMarker {
  /// Create a custom marker for a pulse
  static Future<BitmapDescriptor> createMarkerIcon(
    BuildContext context,
    Pulse pulse, {
    double size = 120,
  }) async {
    // Create a PictureRecorder to draw the marker
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final paint = Paint()..color = Colors.white;

    // Draw the marker
    _drawMarker(canvas, size, pulse, paint);

    // Convert to image
    final picture = pictureRecorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      return BitmapDescriptor.defaultMarker;
    }

    return BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
  }

  /// Draw the marker on the canvas
  static void _drawMarker(
      Canvas canvas, double size, Pulse pulse, Paint paint) {
    final center = Offset(size / 2, size / 2);
    final radius = size / 2 - 8;

    // Draw outer circle
    paint.color = _getColorForPulse(pulse);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 8;
    canvas.drawCircle(center, radius, paint);

    // Draw inner circle
    paint.color = Colors.white;
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 4, paint);

    // Draw emoji or icon
    final textPainter = TextPainter(
      text: TextSpan(
        text: pulse.activityEmoji ?? '📍',
        style: const TextStyle(
          fontSize: 40,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );

    // Draw distance text
    if (pulse.distanceMeters != null) {
      final distanceText = pulse.formattedDistance;
      final distanceTextPainter = TextPainter(
        text: TextSpan(
          text: distanceText,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      distanceTextPainter.layout();
      distanceTextPainter.paint(
        canvas,
        Offset(
          center.dx - distanceTextPainter.width / 2,
          center.dy + radius / 2,
        ),
      );
    }
  }

  /// Get color based on pulse capacity and distance
  static Color _getColorForPulse(Pulse pulse) {
    // If pulse is full, show dark blue
    if (pulse.isFull) {
      return const Color(0xFF0D47A1); // Dark blue
    }

    // If pulse has high capacity (>80%), show medium blue
    if (pulse.maxParticipants != null) {
      final capacityPercentage = pulse.capacityPercentage;
      if (capacityPercentage > 80) {
        return const Color(0xFF1565C0); // Medium-dark blue
      }
    }

    // Otherwise, color based on distance with blue shades
    if (pulse.distanceMeters == null) {
      return const Color(0xFF64B5F6); // Light blue
    }

    if (pulse.distanceMeters! < 200) {
      return const Color(0xFF42A5F5); // Medium-light blue
    } else if (pulse.distanceMeters! < 500) {
      return const Color(0xFF1E88E5); // Medium blue
    } else if (pulse.distanceMeters! < 1000) {
      return const Color(0xFF1976D2); // Medium-dark blue
    } else {
      return const Color(0xFF1565C0); // Dark blue
    }
  }

  /// Create markers for a list of pulses
  static Future<Set<Marker>> createMarkersFromPulses(
    BuildContext context,
    List<Pulse> pulses,
    Function(Pulse) onTap,
  ) async {
    final markers = <Marker>{};

    for (final pulse in pulses) {
      try {
        final markerIcon = await createMarkerIcon(context, pulse);

        markers.add(
          Marker(
            markerId: MarkerId('pulse_${pulse.id}'),
            position: pulse.location,
            icon: markerIcon,
            onTap: () => onTap(pulse),
          ),
        );
      } catch (e) {
        debugPrint('Error creating marker for pulse ${pulse.id}: $e');
        // Fallback to default marker
        markers.add(
          Marker(
            markerId: MarkerId('pulse_${pulse.id}'),
            position: pulse.location,
            onTap: () => onTap(pulse),
          ),
        );
      }
    }

    return markers;
  }
}
