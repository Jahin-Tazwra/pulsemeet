import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';

import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import 'package:provider/provider.dart';

import 'config/env_config.dart';
import 'config/supabase_config.dart';
import 'services/supabase_service.dart';
import 'services/pulse_notifier.dart';
import 'services/notification_service.dart';
import 'services/database_initialization_service.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/connections/user_search_screen.dart';
import 'screens/connections/connections_screen.dart';
import 'screens/connections/connection_requests_screen.dart';
import 'screens/profile/ratings_screen.dart';
import 'models/profile.dart' as app_models;
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await EnvConfig.initialize();

  // Debug: Print Google Maps API key
  debugPrint('Google Maps API Key: ${EnvConfig.googleMapsApiKey}');

  // Initialize Supabase
  await SupabaseConfig.initialize();

  // Create service instances to ensure they're initialized
  final pulseNotifier = PulseNotifier();
  final notificationService = NotificationService();

  // Initialize database schema
  final dbInitService = DatabaseInitializationService();
  await dbInitService.initialize();

  // Create the SupabaseService first
  final supabaseService = SupabaseService();

  runApp(
    MultiProvider(
      providers: [
        Provider<SupabaseService>.value(value: supabaseService),
        Provider(create: (_) => pulseNotifier),
        Provider(create: (_) => notificationService),
        ChangeNotifierProvider(create: (_) => ThemeProvider(supabaseService)),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final StreamSubscription<Uri?> _sub;
  final _appLinks = AppLinks(); // Singleton instance

  @override
  void initState() {
    super.initState();

    // Handle cold-start deep link
    _appLinks.getInitialAppLink().then((uri) async {
      if (uri != null && uri.scheme == 'com.example.pulsemeet') {
        debugPrint('Processing cold-start deep link: $uri');
        try {
          final response =
              await Supabase.instance.client.auth.getSessionFromUrl(uri);
          debugPrint('Cold-start auth response: ${response.session}');
        } catch (e) {
          debugPrint('Error processing cold-start deep link: $e');
        }
      }
    });

    // Listen for warm-start deep links
    _sub = _appLinks.uriLinkStream.listen((uri) async {
      debugPrint('Processing warm-start deep link: $uri');
      if (uri.scheme == 'com.example.pulsemeet') {
        try {
          final response =
              await Supabase.instance.client.auth.getSessionFromUrl(uri);
          debugPrint('Warm-start auth response: ${response.session}');

          // Force refresh the auth state
          final refreshResponse =
              await Supabase.instance.client.auth.refreshSession();
          debugPrint('Session after refresh: ${refreshResponse.session}');
        } catch (e) {
          debugPrint('Error processing warm-start deep link: $e');
        }
      }
    }, onError: (err) {
      debugPrint('🔗 Deep link error: $err');
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supabaseService =
        Provider.of<SupabaseService>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context);

    // Update map theme when app rebuilds due to theme changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      themeProvider.updateMapTheme(context);
    });

    return MaterialApp(
      title: 'PulseMeet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5), // Blue as seed color
          primary: const Color(0xFF1E88E5), // Blue as primary color
          secondary: const Color(0xFF64B5F6), // Lighter blue as secondary
          tertiary: const Color(0xFF42A5F5), // Medium blue as tertiary
          error: const Color(0xFFEF5350), // Red for errors
          brightness: Brightness.light,
          surface: Colors.white,
          onSurface: const Color(0xFF212121), // Dark grey for text on surface
          surfaceTint: const Color(0xFF1E88E5), // Blue tint
        ),
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Roboto',

        // Button themes
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E88E5), // Blue background
            foregroundColor: Colors.white, // White text
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30), // More rounded corners
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1E88E5), // Blue text
            side: const BorderSide(color: Color(0xFF1E88E5)), // Blue border
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30), // More rounded corners
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF1E88E5), // Blue text
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30), // More rounded corners
            ),
          ),
        ),

        // Card settings
        cardColor: Colors.white,

        // AppBar theme
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E88E5), // Blue background
          foregroundColor: Colors.white, // White text
          elevation: 0,
          centerTitle: true,
        ),

        // Bottom navigation bar theme
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          elevation: 8,
          selectedIconTheme: IconThemeData(size: 28),
          unselectedIconTheme: IconThemeData(size: 24),
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal),
          backgroundColor: Colors.white, // White background
          selectedItemColor: Color(0xFF1E88E5), // Blue for selected items
          unselectedItemColor:
              Color(0xFF9E9E9E), // Medium grey for unselected items
        ),

        // Dialog settings

        // Floating action button theme
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: const Color(0xFF1E88E5), // Blue background
          foregroundColor: Colors.white, // White icon
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30), // More rounded corners
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5), // Blue as seed color
          primary: const Color(0xFF1E88E5), // Blue primary color
          secondary: const Color(0xFF64B5F6), // Lighter blue as secondary
          tertiary: const Color(0xFF42A5F5), // Medium blue as tertiary
          error: const Color(0xFFEF5350), // Red for errors
          brightness: Brightness.dark,
          surface: const Color(0xFF121212), // Black background
          surfaceContainer: const Color(0xFF212121), // Dark gray surface
          onSurface: Colors.white, // White text on surface
          onPrimary: Colors.white, // White text on primary
          onSecondary: Colors.white, // White text on secondary
          surfaceTint: const Color(0xFF1E88E5), // Blue tint
        ),
        scaffoldBackgroundColor: const Color(0xFF121212), // Black background
        fontFamily: 'Roboto',
        canvasColor:
            const Color(0xFF121212), // Black background for dialogs, etc.

        // Text themes with proper opacity levels for different text hierarchies
        textTheme: const TextTheme(
          displayLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          displayMedium:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          displaySmall:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          headlineLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          headlineMedium:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          headlineSmall:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          titleLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          titleMedium:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          titleSmall:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
          bodySmall: TextStyle(
              color: Colors.white70), // 70% opacity for less important text
          labelLarge: TextStyle(color: Colors.white),
          labelMedium: TextStyle(color: Colors.white70), // 70% opacity
          labelSmall: TextStyle(color: Colors.white60), // 60% opacity
        ),

        // Button themes
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E88E5), // Blue background
            foregroundColor: Colors.white, // White text
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30), // More rounded corners
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF64B5F6), // Light blue
            side:
                const BorderSide(color: Color(0xFF64B5F6)), // Light blue border
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30), // More rounded corners
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF64B5F6), // Light blue
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30), // More rounded corners
            ),
          ),
        ),

        // Card settings
        cardColor: const Color(0xFF212121), // Dark gray for cards

        // AppBar theme
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212), // Black background
          foregroundColor: Colors.white, // White text
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
        ),

        // Bottom navigation bar theme
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          elevation: 8,
          selectedIconTheme: IconThemeData(size: 28),
          unselectedIconTheme: IconThemeData(size: 24),
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal),
          backgroundColor: Color(0xFF121212), // Black background
          selectedItemColor: Color(0xFF1E88E5), // Blue for selected items
          unselectedItemColor:
              Colors.white60, // White with 60% opacity for unselected items
        ),

        // Dialog settings

        // Floating action button theme
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: const Color(0xFF1E88E5), // Blue background
          foregroundColor: Colors.white, // White icon
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30), // More rounded corners
          ),
        ),

        // Input decoration theme
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF212121), // Dark gray for input fields
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF1E88E5), width: 2),
          ),
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white38),
        ),
      ),
      themeMode:
          themeProvider.flutterThemeMode, // Use user preference or system theme
      routes: {
        '/user_search': (context) => const UserSearchScreen(),
        '/connections': (context) => const ConnectionsScreen(),
        '/connection_requests': (context) => const ConnectionRequestsScreen(),
        '/ratings': (context) {
          final profile =
              ModalRoute.of(context)!.settings.arguments as app_models.Profile;
          return RatingsScreen(profile: profile);
        },
      },
      home: StreamBuilder<bool>(
        stream: supabaseService.authStateChanges,
        builder: (context, snapshot) {
          // Add debug print to see the snapshot state
          debugPrint(
              'Auth state snapshot: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, data: ${snapshot.data}');

          // Show splash screen while waiting for the initial connection
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SplashScreen();
          }

          // Check if authenticated
          final isAuthenticated = snapshot.data ?? false;

          // Debug print the navigation decision
          debugPrint(
              'Navigation decision: isAuthenticated=$isAuthenticated, navigating to ${isAuthenticated ? 'HomeScreen' : 'AuthScreen'}');

          // If user is authenticated, refresh theme preferences
          if (isAuthenticated) {
            // Refresh theme preferences
            final themeProvider =
                Provider.of<ThemeProvider>(context, listen: false);
            themeProvider.refreshThemePreference();
          }

          // Navigate based on authentication state
          return isAuthenticated ? const HomeScreen() : const AuthScreen();
        },
      ),
    );
  }
}
