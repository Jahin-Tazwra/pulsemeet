import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/utils/map_styles.dart';

/// Controller for managing Google Maps theme synchronization
class MapThemeController {
  // Singleton instance
  static final MapThemeController _instance = MapThemeController._internal();

  // Factory constructor to return the singleton instance
  factory MapThemeController() => _instance;

  // Private constructor
  MapThemeController._internal();

  // List of map controllers that need to be updated when theme changes
  final List<GoogleMapController> _controllers = [];

  // Current brightness
  Brightness? _currentBrightness;

  /// Get the number of controllers (for testing)
  int get controllersCount => _controllers.length;

  /// Register a map controller to receive theme updates
  void registerController(
      GoogleMapController controller, BuildContext context) {
    if (!_controllers.contains(controller)) {
      _controllers.add(controller);

      // Apply the current theme immediately
      final brightness = Theme.of(context).brightness;
      _applyThemeToController(controller, brightness);
    }
  }

  /// Unregister a map controller when it's no longer needed
  void unregisterController(GoogleMapController controller) {
    _controllers.remove(controller);
  }

  /// Update all registered map controllers with the new theme
  void updateTheme(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    // Only update if brightness has changed
    if (_currentBrightness != brightness) {
      _currentBrightness = brightness;

      // Update all controllers
      for (final controller in _controllers) {
        _applyThemeToController(controller, brightness);
      }
    }
  }

  /// Apply theme to a specific controller
  void _applyThemeToController(
      GoogleMapController controller, Brightness brightness) {
    try {
      if (brightness == Brightness.dark) {
        controller.setMapStyle(MapStyles.darkMapStyle);
      } else {
        controller.setMapStyle(null); // Use default light style
      }
    } catch (e) {
      debugPrint('Error applying map style: $e');
    }
  }

  /// Clear all controllers (useful for testing or app reset)
  void clearControllers() {
    _controllers.clear();
    _currentBrightness = null;
  }
}
