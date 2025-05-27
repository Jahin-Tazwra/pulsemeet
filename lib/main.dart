import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import 'package:provider/provider.dart';

import 'config/env_config.dart';
import 'config/supabase_config.dart';
import 'services/supabase_service.dart';
import 'services/pulse_notifier.dart';
import 'services/notification_service.dart';
import 'services/firebase_messaging_service.dart';
import 'services/database_initialization_service.dart';
import 'services/encryption_service.dart';
import 'services/key_management_service.dart';
import 'services/encrypted_message_service.dart';
import 'services/optimistic_ui_service.dart';
import 'services/conversation_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/connections/user_search_screen.dart';
import 'screens/connections/connections_screen.dart';
import 'screens/connections/connection_requests_screen.dart';
import 'screens/profile/ratings_screen.dart';
import 'screens/pulse/pulse_details_screen.dart';
import 'screens/pulse/pulse_search_screen.dart';
import 'models/profile.dart' as app_models;
import 'providers/theme_provider.dart';
import 'services/analytics_service.dart';

// Global navigator key for accessing the navigator from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register Firebase background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Load environment variables
  await EnvConfig.initialize();
  debugPrint('Environment variables loaded successfully');
  debugPrint('🚀 Main function started - about to initialize services...');

  // Debug: Print Google Maps API key
  debugPrint('Google Maps API Key: ${EnvConfig.googleMapsApiKey}');

  // Initialize Supabase
  await SupabaseConfig.initialize();

  // Create service instances to ensure they're initialized
  final pulseNotifier = PulseNotifier();
  final notificationService = NotificationService();
  final firebaseMessagingService = FirebaseMessagingService();

  // Initialize encryption services
  final encryptionService = EncryptionService();
  final keyManagementService = KeyManagementService();
  final encryptedMessageService = EncryptedMessageService();

  // Initialize Firebase messaging for push notifications
  try {
    debugPrint('🔥 Initializing Firebase messaging...');
    await firebaseMessagingService.initialize();
    debugPrint('✅ Firebase messaging initialized successfully');

    // Test WhatsApp-style notifications after a delay (debug mode only)
    if (kDebugMode) {
      Future.delayed(const Duration(seconds: 5), () async {
        debugPrint('🧪 Testing WhatsApp-style notification automatically...');
        try {
          await firebaseMessagingService.testWhatsAppStyleNotification();
          debugPrint('✅ Automatic WhatsApp-style notification test completed');
        } catch (e) {
          debugPrint('❌ Automatic WhatsApp-style notification test failed: $e');
        }
      });
    }
  } catch (e) {
    debugPrint('❌ Firebase messaging initialization failed: $e');
    // Continue without push notifications if Firebase fails
  }

  // Initialize ConversationService early to ensure real-time detection is set up
  try {
    debugPrint('💬 Initializing ConversationService...');
    final conversationService = ConversationService();
    // The service will initialize itself automatically when accessed
    debugPrint('✅ ConversationService initialized successfully');
  } catch (e) {
    debugPrint('❌ ConversationService initialization failed: $e');
    // Continue without conversation service if it fails
  }

  // Initialize OptimisticUIService early to set up status subscription
  debugPrint('🔧 About to initialize OptimisticUIService...');
  final optimisticUIService = OptimisticUIService.instance;
  debugPrint(
      '✅ OptimisticUIService initialized during app startup: $optimisticUIService');

  // Initialize database schema with timeout
  try {
    debugPrint('Starting database initialization...');
    final dbInitService = DatabaseInitializationService();
    await dbInitService.initialize().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('Database initialization timed out after 10 seconds');
        throw TimeoutException(
            'Database initialization timeout', const Duration(seconds: 10));
      },
    );
    debugPrint('Database initialization completed successfully');
  } catch (e) {
    debugPrint('Database initialization failed: $e');
    // Continue app startup even if database initialization fails
    debugPrint('Continuing app startup without database initialization');
  }

  // Initialize encryption services
  try {
    debugPrint('Starting encryption services initialization...');
    await encryptionService.initialize();
    await keyManagementService.initialize();
    await encryptedMessageService.initialize();
    debugPrint('Encryption services initialization completed successfully');
  } catch (e) {
    debugPrint('Encryption services initialization failed: $e');
    // Continue app startup even if encryption initialization fails
    debugPrint('Continuing app startup without encryption initialization');
  }

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
      if (uri != null) {
        debugPrint('Processing cold-start deep link: $uri');

        // Handle auth deep links
        if (uri.scheme == 'com.example.pulsemeet' &&
            uri.host == 'login-callback') {
          try {
            debugPrint('Processing cold-start login callback: $uri');

            // Extract the fragment (part after #) which contains the auth data
            final fragment = uri.fragment;
            if (fragment.isNotEmpty) {
              debugPrint('Auth fragment found: $fragment');

              // Create a new URI with the fragment converted to query parameters
              final authUri = Uri.parse('https://dummy.com/auth?$fragment');

              // Extract the access token
              final accessToken = authUri.queryParameters['access_token'];
              if (accessToken != null) {
                debugPrint('Access token found, setting session');

                // Parse refresh token if available
                final refreshToken = authUri.queryParameters['refresh_token'];

                debugPrint(
                    'Auth details: accessToken length=${accessToken.length}, refreshToken=${refreshToken != null ? 'available' : 'not available'}');

                try {
                  // Set the session directly
                  await Supabase.instance.client.auth.setSession(accessToken);

                  // Get the current user to verify authentication worked
                  final currentUser = Supabase.instance.client.auth.currentUser;
                  if (currentUser != null) {
                    debugPrint('User authenticated: ${currentUser.id}');
                    debugPrint('User email: ${currentUser.email}');
                  } else {
                    debugPrint(
                        'Failed to authenticate user - currentUser is null');
                  }

                  debugPrint('Auth state updated successfully');
                } catch (e) {
                  debugPrint('Error setting session: $e');
                }
              }
            }
          } catch (e) {
            debugPrint('Error processing cold-start auth deep link: $e');
          }
        }
        // Handle pulse deep links
        else if (_isPulseDeepLink(uri)) {
          _handlePulseDeepLink(uri);
        }
      }
    });

    // Listen for warm-start deep links
    _sub = _appLinks.uriLinkStream.listen((uri) async {
      debugPrint('Processing warm-start deep link: $uri');

      // Handle auth deep links
      if (uri.scheme == 'com.example.pulsemeet' &&
          uri.host == 'login-callback') {
        try {
          debugPrint('Processing login callback: $uri');

          // Extract the fragment (part after #) which contains the auth data
          final fragment = uri.fragment;
          if (fragment.isNotEmpty) {
            debugPrint('Auth fragment found: $fragment');

            // Create a new URI with the fragment converted to query parameters
            final authUri = Uri.parse('https://dummy.com/auth?$fragment');

            // Extract the access token
            final accessToken = authUri.queryParameters['access_token'];
            if (accessToken != null) {
              debugPrint('Access token found, setting session');

              // Parse refresh token if available
              final refreshToken = authUri.queryParameters['refresh_token'];

              debugPrint(
                  'Auth details: accessToken length=${accessToken.length}, refreshToken=${refreshToken != null ? 'available' : 'not available'}');

              try {
                // Try to manually set the session
                await Supabase.instance.client.auth.setSession(accessToken);

                // Get the current user to verify authentication worked
                final currentUser = Supabase.instance.client.auth.currentUser;
                if (currentUser != null) {
                  debugPrint('User authenticated: ${currentUser.id}');
                  debugPrint('User email: ${currentUser.email}');

                  // Force a refresh of the auth state
                  await Supabase.instance.client.auth.refreshSession();

                  // Navigate to home screen
                  if (navigatorKey.currentContext != null) {
                    Navigator.of(navigatorKey.currentContext!)
                        .pushAndRemoveUntil(
                            MaterialPageRoute(
                                builder: (context) => const HomeScreen()),
                            (route) => false);
                  }
                } else {
                  debugPrint(
                      'Failed to authenticate user - currentUser is null');
                }

                debugPrint('Auth state updated successfully');
              } catch (e) {
                debugPrint('Error during authentication: $e');

                // Try to get the session from URL as a fallback
                try {
                  final response = await Supabase.instance.client.auth
                      .getSessionFromUrl(uri);
                  debugPrint('Got session from URL: ${response.session}');

                  // Session is always available in the response
                  // Navigate to home screen
                  if (navigatorKey.currentContext != null) {
                    Navigator.of(navigatorKey.currentContext!)
                        .pushAndRemoveUntil(
                            MaterialPageRoute(
                                builder: (context) => const HomeScreen()),
                            (route) => false);
                  }
                } catch (e2) {
                  debugPrint('Error in fallback authentication: $e2');
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error processing warm-start auth deep link: $e');
        }
      }
      // Handle pulse deep links
      else if (_isPulseDeepLink(uri)) {
        _handlePulseDeepLink(uri);
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

  /// Check if a URI is a pulse deep link
  bool _isPulseDeepLink(Uri uri) {
    // Check for app scheme links (pulsemeet://pulse/CODE)
    if (uri.scheme == 'pulsemeet' && uri.path.startsWith('/pulse/')) {
      return true;
    }

    // Check for web links (https://pulsemeet.app/pulse/CODE)
    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.host == 'pulsemeet.app' || uri.host == 'www.pulsemeet.app') &&
        uri.path.startsWith('/pulse/')) {
      return true;
    }

    return false;
  }

  /// Handle a pulse deep link
  void _handlePulseDeepLink(Uri uri) async {
    debugPrint('Handling pulse deep link: $uri');

    // Extract the pulse code from the URI
    String? pulseCode;

    if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'pulse') {
      pulseCode = uri.pathSegments[1];
    }

    if (pulseCode == null || pulseCode.isEmpty) {
      debugPrint('Invalid pulse code in deep link');
      return;
    }

    debugPrint('Extracted pulse code: $pulseCode');

    // Check if this is a new install
    final prefs = await SharedPreferences.getInstance();
    final isFirstRun = prefs.getBool('is_first_run') ?? true;

    if (isFirstRun) {
      // Track app install from shared link
      final analyticsService = AnalyticsService();
      await analyticsService.trackAppInstallFromShare(pulseCode);

      // Mark as not first run
      await prefs.setBool('is_first_run', false);
    }

    // Store the pulse code to be handled after the app is fully initialized
    _pendingPulseCode = pulseCode;

    // If the app is already initialized, navigate to the pulse
    if (_isAppInitialized) {
      _navigateToPulseByCode(pulseCode);
    }
  }

  /// Navigate to a pulse by code
  Future<void> _navigateToPulseByCode(String code) async {
    debugPrint('Navigating to pulse with code: $code');

    // Get the SupabaseService
    final supabaseService = Provider.of<SupabaseService>(
      navigatorKey.currentContext!,
      listen: false,
    );

    // Check if the user is authenticated
    if (!supabaseService.isAuthenticated) {
      debugPrint('User not authenticated, storing pulse code for later');
      // Store the code to be handled after authentication
      _pendingPulseCode = code;
      return;
    }

    // Look up the pulse by code
    final pulse = await supabaseService.getPulseByShareCode(code);

    if (pulse == null) {
      debugPrint('Pulse not found for code: $code');

      // Show a snackbar if the app is initialized
      if (_isAppInitialized && navigatorKey.currentContext != null) {
        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
          SnackBar(content: Text('Pulse not found for code: $code')),
        );
      }
      return;
    }

    // Track pulse view from shared link
    final analyticsService = AnalyticsService();
    await analyticsService.trackPulseViewFromShare(pulse.id, code);

    // Navigate to the pulse details screen
    if (_isAppInitialized && navigatorKey.currentContext != null) {
      Navigator.push(
        navigatorKey.currentContext!,
        MaterialPageRoute(
          builder: (context) => PulseDetailsScreen(pulse: pulse),
        ),
      );
    }
  }

  // Variables for handling deep links
  String? _pendingPulseCode;
  bool _isAppInitialized = false;

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
      navigatorKey: navigatorKey,
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
        '/pulse_search': (context) => const PulseSearchScreen(),
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

          // Theme preferences are now loaded automatically by ThemeProvider

          // Mark the app as initialized
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _isAppInitialized = true;

            // Check if we have a pending pulse code to handle
            if (_pendingPulseCode != null && isAuthenticated) {
              _navigateToPulseByCode(_pendingPulseCode!);
              _pendingPulseCode = null;
            }
          });

          // Navigate based on authentication state
          return isAuthenticated ? const HomeScreen() : const AuthScreen();
        },
      ),
    );
  }
}
