import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mockito/mockito.dart';
import 'package:pulsemeet/controllers/map_theme_controller.dart';
import 'package:pulsemeet/utils/map_styles.dart';

// Mock GoogleMapController
class MockGoogleMapController extends Mock implements GoogleMapController {}

// Mock BuildContext
class MockBuildContext extends Mock implements BuildContext {}

void main() {
  group('MapThemeController Tests', () {
    late MapThemeController controller;
    late MockGoogleMapController mockMapController;
    late MockBuildContext mockContext;

    setUp(() {
      controller = MapThemeController();
      mockMapController = MockGoogleMapController();
      mockContext = MockBuildContext();
    });

    test('registerController adds controller to list', () {
      // Arrange
      when(mockContext.brightness).thenReturn(Brightness.light);

      // Act
      controller.registerController(mockMapController, mockContext);

      // Assert
      expect(controller.controllersCount, 1);
    });

    test('unregisterController removes controller from list', () {
      // Arrange
      when(mockContext.brightness).thenReturn(Brightness.light);
      controller.registerController(mockMapController, mockContext);

      // Act
      controller.unregisterController(mockMapController);

      // Assert
      expect(controller.controllersCount, 0);
    });

    test('updateTheme applies dark theme when brightness is dark', () {
      // Arrange
      when(mockContext.brightness).thenReturn(Brightness.dark);
      controller.registerController(mockMapController, mockContext);

      // Act
      controller.updateTheme(mockContext);

      // Assert
      verify(mockMapController.setMapStyle(MapStyles.darkMapStyle)).called(1);
    });

    test('updateTheme applies light theme when brightness is light', () {
      // Arrange
      when(mockContext.brightness).thenReturn(Brightness.light);
      controller.registerController(mockMapController, mockContext);

      // Act
      controller.updateTheme(mockContext);

      // Assert
      verify(mockMapController.setMapStyle(null)).called(1);
    });
  });
}
