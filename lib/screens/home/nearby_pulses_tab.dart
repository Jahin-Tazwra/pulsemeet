import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/services/supabase_service.dart';
import 'package:pulsemeet/services/pulse_notifier.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'package:pulsemeet/widgets/pulse_card.dart';
import 'package:pulsemeet/screens/pulse/pulse_details_screen.dart';
import 'package:pulsemeet/screens/pulse/location_selection_screen.dart';
import 'package:pulsemeet/screens/home/nearby_pulses_map_view.dart';

/// Tab showing nearby pulses
class NearbyPulsesTab extends StatefulWidget {
  const NearbyPulsesTab({super.key});

  @override
  State<NearbyPulsesTab> createState() => _NearbyPulsesTabState();
}

class _NearbyPulsesTabState extends State<NearbyPulsesTab> {
  List<Pulse> _nearbyPulses = [];
  bool _isLoading = true;
  bool _isSearchingForClosestPulse = false;
  String? _errorMessage;
  Position? _currentPosition;
  bool _showMapView = true; // Default to map view
  late final StreamSubscription<Pulse> _pulseCreatedSubscription;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();

    // Listen for all pulse creation events to update the UI
    // This ensures all pulses are visible regardless of distance
    _pulseCreatedSubscription =
        PulseNotifier().onPulseCreated.listen((newPulse) {
      debugPrint(
          'NearbyPulsesTab: Received pulse created event: ${newPulse.id}');
      // Refresh the list of nearby pulses when a new pulse is created
      _fetchNearbyPulses();
    });
  }

  @override
  void dispose() {
    _pulseCreatedSubscription.cancel();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Location permission denied';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Location permission permanently denied';
        });
        return;
      }

      // Get current position with high accuracy
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Update state with the new position
      setState(() {
        _currentPosition = position;
      });

      // Update the PulseNotifier with the current location
      if (mounted) {
        final pulseNotifier =
            Provider.of<PulseNotifier>(context, listen: false);
        pulseNotifier.updateUserLocationFromPosition(position);
      }

      // Fetch nearby pulses
      await _fetchNearbyPulses();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error getting location: ${e.toString()}';
      });
    }
  }

  Future<void> _fetchNearbyPulses() async {
    if (_currentPosition == null) {
      // If we don't have a position yet, try to get it first
      await _getCurrentLocation();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabaseService =
          Provider.of<SupabaseService>(context, listen: false);

      debugPrint('Fetching nearby pulses from position: '
          '(${_currentPosition!.latitude}, ${_currentPosition!.longitude})');

      // Use a moderate search radius by default (10km)
      // This will show nearby pulses but not too many
      final pulses = await supabaseService.getNearbyPulses(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        maxDistance: 10000, // 10km radius
      );

      debugPrint('Received ${pulses.length} pulses');

      if (mounted) {
        setState(() {
          _nearbyPulses = pulses;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error in _fetchNearbyPulses: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error fetching pulses: ${e.toString()}';
        });
      }
    }
  }

  /// Find all pulses regardless of distance
  Future<void> _findAllPulses() async {
    if (_currentPosition == null) {
      // If we don't have a position yet, try to get it first
      await _getCurrentLocation();
      return;
    }

    setState(() {
      _isSearchingForClosestPulse = true;
    });

    try {
      final supabaseService =
          Provider.of<SupabaseService>(context, listen: false);

      // Use a very large search radius to find all pulses
      // 1,000,000 meters = 1,000 km, which should cover most reasonable distances
      final pulses = await supabaseService.getNearbyPulses(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        maxDistance: 1000000, // 1000km radius to find virtually all pulses
      );

      if (mounted) {
        setState(() {
          // Always update the pulses list, even if empty
          _nearbyPulses = pulses;
          _isSearchingForClosestPulse = false;
        });

        // Show a message if no pulses were found
        if (pulses.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No pulses found anywhere. Try creating one!'),
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          // Show a message with the number of pulses found
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Found ${pulses.length} pulses. Tap "Find Closest Pulse" to navigate through them.'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error finding all pulses: $e');
      if (mounted) {
        setState(() {
          _isSearchingForClosestPulse = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error finding pulses: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Handle the find closest pulse button press
  void _handleFindClosestPulse(bool isLoading) {
    setState(() {
      _isSearchingForClosestPulse = isLoading;
    });

    // If we're starting the search and there are no pulses or only a few nearby,
    // try to find all pulses regardless of distance
    if (isLoading && _nearbyPulses.length < 2) {
      // Delay slightly to allow the loading indicator to show
      Future.delayed(const Duration(milliseconds: 100), () {
        _findAllPulses();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'PulseMeet',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          centerTitle: true,
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
              backgroundColor:
                  Colors.white.withAlpha(75), // Semi-transparent white
              child: const Icon(
                Icons.person,
                color: Colors.white, // White icon
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(
                Icons.search,
                color: Colors.white, // White icon
              ),
              onPressed: () {
                Navigator.pushNamed(context, '/user_search');
              },
              tooltip: 'Search for users',
            ),
          ],
        ),
        body: Column(
          children: [
            // View toggle
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF64B5F6), // Light blue background
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _showMapView = true;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _showMapView
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: _showMapView
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(25),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            'Map',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _showMapView
                                  ? const Color(
                                      0xFF1E88E5) // Blue text when selected
                                  : Colors.white, // White text when unselected
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _showMapView = false;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !_showMapView
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: !_showMapView
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(25),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            'List',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: !_showMapView
                                  ? const Color(
                                      0xFF1E88E5) // Blue text when selected
                                  : Colors.white, // White text when unselected
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Main content
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const LocationSelectionScreen(),
              ),
            ).then((_) {
              // Refresh the list when returning from create screen
              _fetchNearbyPulses();
            });
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildBody() {
    // Convert current position to LatLng for map view
    LatLng? currentLatLng;
    if (_currentPosition != null) {
      currentLatLng = LatLng(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
    }

    // If showing map view, always display the map regardless of pulse availability
    if (_showMapView) {
      // Always show the map, even when loading
      // The map will show its own loading indicator when waiting for location
      if (_isLoading) {
        return Stack(
          children: [
            NearbyPulsesMapView(
              pulses: _nearbyPulses,
              currentLocation:
                  currentLatLng, // This might be null while loading
              onRefresh: _fetchNearbyPulses,
              searchRadius: 10000, // Default search radius in meters (10km)
              onFindClosestPulse: _handleFindClosestPulse,
            ),
            // Only show the loading indicator if we don't have a location yet
            if (currentLatLng == null)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF1E88E5)),
              ),
          ],
        );
      }

      // Show error message overlay on top of map if there's an error
      if (_errorMessage != null) {
        return Stack(
          children: [
            NearbyPulsesMapView(
              pulses: _nearbyPulses,
              currentLocation: currentLatLng,
              onRefresh: _fetchNearbyPulses,
              searchRadius: 10000, // Default search radius in meters (10km)
              onFindClosestPulse: _handleFindClosestPulse,
            ),
            Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(230), // ~0.9 opacity
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(25), // ~0.1 opacity
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _getCurrentLocation,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }

      // Normal map view (with or without pulses)
      return Stack(
        children: [
          NearbyPulsesMapView(
            pulses: _nearbyPulses,
            currentLocation: currentLatLng,
            onRefresh: _fetchNearbyPulses,
            searchRadius: 10000, // Default search radius in meters (10km)
            onFindClosestPulse: _handleFindClosestPulse,
          ),

          // Show loading indicator when searching for closest pulse
          if (_isSearchingForClosestPulse)
            Container(
              color:
                  Colors.white.withAlpha(230), // Semi-transparent white overlay
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF1E88E5)),
                    SizedBox(height: 16),
                    Text(
                      'Finding closest pulse...',
                      style: TextStyle(
                        color: Color(0xFF1E88E5),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    } else {
      // List view - show appropriate states for loading, error, or empty list
      if (_isLoading) {
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFF1E88E5)),
        );
      }

      if (_errorMessage != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _getCurrentLocation,
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }

      if (_nearbyPulses.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.location_off,
                size: 64,
                color: Color(0xFF64B5F6), // Light blue
              ),
              const SizedBox(height: 16),
              const Text(
                'No pulses found nearby',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Try creating a new pulse!',
                style: TextStyle(color: Color(0xFF64B5F6)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchNearbyPulses,
                child: const Text('Refresh'),
              ),
            ],
          ),
        );
      }

      // List view with pulses
      return RefreshIndicator(
        onRefresh: _fetchNearbyPulses,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _nearbyPulses.length,
          itemBuilder: (context, index) {
            final pulse = _nearbyPulses[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: PulseCard(
                pulse: pulse,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PulseDetailsScreen(pulse: pulse),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );
    }
  }
}
