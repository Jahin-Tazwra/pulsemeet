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
  String? _errorMessage;
  Position? _currentPosition;
  bool _showMapView = true; // Default to map view
  late final StreamSubscription<Pulse> _pulseCreatedSubscription;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();

    // Listen for pulse creation events
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

      // Get current position
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
      });

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

      final pulses = await supabaseService.getNearbyPulses(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PulseMeet'),
        centerTitle: true,
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: const Icon(Icons.person),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              // TODO: Navigate to notifications screen
            },
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
                color: Colors.blue.shade100,
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
                          color:
                              _showMapView ? Colors.blue : Colors.transparent,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          'Map',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _showMapView ? Colors.white : Colors.black,
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
                          color:
                              !_showMapView ? Colors.blue : Colors.transparent,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          'List',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: !_showMapView ? Colors.white : Colors.black,
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
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
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
              color: Colors.grey,
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
              style: TextStyle(color: Colors.grey),
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

    // Convert current position to LatLng for map view
    LatLng? currentLatLng;
    if (_currentPosition != null) {
      currentLatLng = LatLng(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
    }

    // Show either map view or list view based on toggle
    if (_showMapView) {
      return NearbyPulsesMapView(
        pulses: _nearbyPulses,
        currentLocation: currentLatLng,
        onRefresh: _fetchNearbyPulses,
      );
    } else {
      // List view
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
