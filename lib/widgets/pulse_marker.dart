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
  static void _drawMarker(Canvas canvas, double size, Pulse pulse, Paint paint) {
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

  /// Get color based on pulse type or distance
  static Color _getColorForPulse(Pulse pulse) {
    // You can customize this based on pulse properties
    if (pulse.distanceMeters == null) {
      return Colors.blue;
    }
    
    // Color based on distance
    if (pulse.distanceMeters! < 200) {
      return Colors.green;
    } else if (pulse.distanceMeters! < 500) {
      return Colors.orange;
    } else if (pulse.distanceMeters! < 1000) {
      return Colors.deepPurple;
    } else {
      return Colors.red;
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
