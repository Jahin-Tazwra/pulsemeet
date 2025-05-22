import 'package:flutter/material.dart';
import 'package:pulsemeet/controllers/map_theme_controller.dart';
import 'package:pulsemeet/models/profile.dart' as app_models;
import 'package:pulsemeet/services/supabase_service.dart';

/// Provider for managing the app's theme
class ThemeProvider extends ChangeNotifier {
  final SupabaseService _supabaseService;
  final MapThemeController _mapThemeController = MapThemeController();
  app_models.ThemeMode _themeMode = app_models.ThemeMode.system;
  bool _isLoading = true;

  /// Constructor
  ThemeProvider(this._supabaseService) {
    // Defer the initial load to avoid calling notifyListeners during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadThemePreference();
    });
  }

  /// Get the map theme controller
  MapThemeController get mapThemeController => _mapThemeController;

  /// Get the current theme mode
  app_models.ThemeMode get themeMode => _themeMode;

  /// Get the Flutter ThemeMode
  ThemeMode get flutterThemeMode {
    switch (_themeMode) {
      case app_models.ThemeMode.light:
        return ThemeMode.light;
      case app_models.ThemeMode.dark:
        return ThemeMode.dark;
      case app_models.ThemeMode.system:
        return ThemeMode.system;
    }
  }

  /// Check if the provider is loading
  bool get isLoading => _isLoading;

  /// Load the theme preference from the user's profile
  Future<void> _loadThemePreference() async {
    _isLoading = true;
    notifyListeners();

    try {
      final userId = _supabaseService.currentUserId;
      if (userId != null) {
        final profile = await _supabaseService.getProfile(userId);
        _themeMode = profile.themeMode;
      }
    } catch (e) {
      debugPrint('Error loading theme preference: $e');
      // Default to system theme if there's an error
      _themeMode = app_models.ThemeMode.system;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set the theme mode
  Future<void> setThemeMode(app_models.ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    notifyListeners();

    try {
      final userId = _supabaseService.currentUserId;
      if (userId != null) {
        await _supabaseService.updateThemeMode(userId, mode);
      }
    } catch (e) {
      debugPrint('Error saving theme preference: $e');
      // If there's an error, revert to the previous theme
      _loadThemePreference();
    }
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    // We can't update the map theme here directly because we don't have a BuildContext
    // The widgets using this provider will call updateMapTheme when they rebuild
  }

  /// Update map theme based on current context
  void updateMapTheme(BuildContext context) {
    _mapThemeController.updateTheme(context);
  }

  /// Refresh the theme preference from the user's profile
  Future<void> refreshThemePreference() async {
    await _loadThemePreference();
  }
}
