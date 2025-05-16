import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';

import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import 'package:provider/provider.dart';

import 'config/env_config.dart';
import 'config/supabase_config.dart';
import 'services/supabase_service.dart';
import 'services/pulse_notifier.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await EnvConfig.initialize();

  // Debug: Print Google Maps API key
  debugPrint('Google Maps API Key: ${EnvConfig.googleMapsApiKey}');

  // Initialize Supabase
  await SupabaseConfig.initialize();

  // Create a PulseNotifier instance to ensure it's initialized
  final pulseNotifier = PulseNotifier();

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => SupabaseService()),
        Provider(create: (_) => pulseNotifier),
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

    return MaterialApp(
      title: 'PulseMeet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          primary: const Color(0xFF6750A4),
          secondary: const Color(0xFF03DAC6),
          surface: Colors.white,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
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

          // Navigate based on authentication state
          return isAuthenticated ? const HomeScreen() : const AuthScreen();
        },
      ),
    );
  }
}
