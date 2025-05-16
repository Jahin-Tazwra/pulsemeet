import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'package:pulsemeet/services/supabase_service.dart';
import 'package:pulsemeet/screens/pulse/pulse_chat_screen.dart';

/// Screen for viewing pulse details
class PulseDetailsScreen extends StatefulWidget {
  final Pulse pulse;

  const PulseDetailsScreen({super.key, required this.pulse});

  @override
  State<PulseDetailsScreen> createState() => _PulseDetailsScreenState();
}

class _PulseDetailsScreenState extends State<PulseDetailsScreen> {
  bool _isJoining = false;
  bool _isLeaving = false;
  bool _hasJoined = false;
  bool _mapReady = false;
  bool _isMapInitialized = false;

  // Flag to track if we're viewing the user's location
  bool _isViewingUserLocation = false;

  // Flag to prevent showing the snackbar multiple times
  bool _hasShownLocationSnackbar = false;

  // Timestamp of the last snackbar shown
  DateTime? _lastSnackbarTime;

  // Completer to handle map initialization
  final Completer<GoogleMapController> _mapControllerCompleter =
      Completer<GoogleMapController>();

  // Map elements
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();

    // Debug log the pulse location
    debugPrint(
        'PulseDetailsScreen - Pulse location: ${widget.pulse.location.latitude}, ${widget.pulse.location.longitude}');
    debugPrint('PulseDetailsScreen - Pulse ID: ${widget.pulse.id}');
    debugPrint('PulseDetailsScreen - Pulse title: ${widget.pulse.title}');

    // Validate the pulse location
    _validatePulseLocation();

    // Initialize map elements immediately
    _setupMapElements();

    // Check if the user has already joined this pulse
    _checkJoinStatus();
  }

  void _validatePulseLocation() {
    // Check if the pulse location is at (0,0), which indicates a parsing error
    if (widget.pulse.location.latitude == 0 &&
        widget.pulse.location.longitude == 0) {
      debugPrint(
          'WARNING: Pulse location is at (0,0), which is likely incorrect');

      // Try to fetch the pulse again from the database
      _refreshPulseData();
    }
  }

  Future<void> _refreshPulseData() async {
    try {
      final supabaseService = Provider.of<SupabaseService>(
        context,
        listen: false,
      );

      // Fetch the pulse by ID
      final refreshedPulse =
          await supabaseService.getPulseById(widget.pulse.id);

      if (refreshedPulse != null && mounted) {
        // Check if the refreshed pulse has valid coordinates
        if (refreshedPulse.location.latitude != 0 ||
            refreshedPulse.location.longitude != 0) {
          debugPrint('Successfully refreshed pulse with valid coordinates: '
              '${refreshedPulse.location.latitude}, ${refreshedPulse.location.longitude}');

          // Update the UI with the refreshed pulse data
          setState(() {
            // We can't directly update widget.pulse since it's final,
            // but we can update our markers and circles with the new location
            _setupMapElementsWithLocation(
                refreshedPulse.location, refreshedPulse.radius);

            // Center the map on the new location
            _animateToPosition(refreshedPulse.location);
          });
        } else {
          debugPrint('Refreshed pulse still has invalid coordinates');

          // As a last resort, try to fetch the pulse directly from the database with raw SQL
          _fetchPulseWithRawSQL(widget.pulse.id);
        }
      }
    } catch (e) {
      debugPrint('Error refreshing pulse data: $e');
    }
  }

  Future<void> _fetchPulseWithRawSQL(String pulseId) async {
    try {
      final supabaseService = Provider.of<SupabaseService>(
        context,
        listen: false,
      );

      // Use a raw SQL query to extract the coordinates
      final response = await supabaseService.client.rpc(
        'get_pulse_coordinates',
        params: {
          'pulse_id': pulseId,
        },
      );

      if (response != null && response is Map) {
        debugPrint('Raw SQL response: $response');

        if (response['latitude'] != null && response['longitude'] != null) {
          final lat = double.parse(response['latitude'].toString());
          final lng = double.parse(response['longitude'].toString());

          debugPrint('Extracted coordinates from raw SQL: lat=$lat, lng=$lng');

          if (lat != 0 || lng != 0) {
            final location = LatLng(lat, lng);

            setState(() {
              _setupMapElementsWithLocation(location, widget.pulse.radius);
              _animateToPosition(location);
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching pulse with raw SQL: $e');
    }
  }

  @override
  void dispose() {
    // Hide any snackbars that might be showing
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    // Dispose of the map controller when the widget is disposed
    _disposeMapController();
    super.dispose();
  }

  Future<void> _disposeMapController() async {
    if (_mapControllerCompleter.isCompleted) {
      final controller = await _mapControllerCompleter.future;
      controller.dispose();
    }
  }

  Future<void> _checkJoinStatus() async {
    try {
      final supabaseService = Provider.of<SupabaseService>(
        context,
        listen: false,
      );

      // Get the current user ID
      final userId = supabaseService.currentUserId;
      if (userId == null) return;

      // Check if the user is the creator (automatically joined)
      if (userId == widget.pulse.creatorId) {
        setState(() {
          _hasJoined = true;
        });
        return;
      }

      // Check if the user has joined this pulse
      // We'll use the existing methods in SupabaseService
      // Get joined pulses and check if this pulse is in the list
      final joinedPulses = await supabaseService.getJoinedPulses();
      final hasJoined =
          joinedPulses.any((pulse) => pulse.id == widget.pulse.id);

      if (mounted) {
        setState(() {
          _hasJoined = hasJoined;
        });
      }
    } catch (e) {
      debugPrint('Error checking join status: $e');
    }
  }

  void _setupMapElements() {
    // Use the location from the widget.pulse
    _setupMapElementsWithLocation(widget.pulse.location, widget.pulse.radius);
  }

  void _setupMapElementsWithLocation(LatLng location, int radius) {
    // Clear existing markers and circles
    _markers.clear();
    _circles.clear();

    // Debug log the marker position
    debugPrint(
        'Setting up marker at: ${location.latitude}, ${location.longitude}');

    // Create marker for pulse location with a custom icon
    _markers.add(
      Marker(
        markerId: const MarkerId('pulse_location'),
        position: location,
        infoWindow: InfoWindow(
          title: widget.pulse.title,
          snippet: widget.pulse.activityEmoji ?? 'Pulse',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        // Make sure the marker is visible
        visible: true,
        // Add a slight animation when the marker is tapped
        onTap: () {
          _animateToPosition(location);
        },
        // Ensure the marker is flat and anchored correctly
        flat: false,
        anchor: const Offset(0.5, 1.0),
        zIndex: 2,
      ),
    );

    // Create circle for pulse radius with better visibility
    _circles.add(
      Circle(
        circleId: const CircleId('pulse_radius'),
        center: location,
        radius: radius.toDouble(),
        fillColor: Colors.blue.withAlpha(50), // Slightly transparent blue
        strokeColor: Colors.blue,
        strokeWidth: 2,
        visible: true,
        zIndex: 1,
      ),
    );

    setState(() {
      _mapReady = true;
    });
  }

  // Method to animate the camera to a specific position
  Future<void> _animateToPosition(LatLng position) async {
    try {
      // If we're animating to the pulse location, reset the user location flag
      if (position.latitude == widget.pulse.location.latitude &&
          position.longitude == widget.pulse.location.longitude) {
        setState(() {
          _isViewingUserLocation = false;
          // Hide any existing snackbars
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        });
      }

      if (_mapControllerCompleter.isCompleted) {
        final controller = await _mapControllerCompleter.future;
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: position,
              zoom: 15.0,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error animating camera: $e');
    }
  }

  // Method to handle map creation
  void _onMapCreated(GoogleMapController controller) {
    debugPrint('Map created successfully');

    if (!_mapControllerCompleter.isCompleted) {
      // Complete the completer with the controller
      _mapControllerCompleter.complete(controller);

      // Get the exact pulse location
      final pulseLocation = widget.pulse.location;
      debugPrint(
          'Centering map on: ${pulseLocation.latitude}, ${pulseLocation.longitude}');

      // Check if we have valid coordinates
      if (pulseLocation.latitude == 0 && pulseLocation.longitude == 0) {
        debugPrint(
            'Invalid coordinates detected in _onMapCreated, attempting to refresh pulse data');
        // Try to refresh the pulse data to get valid coordinates
        _refreshPulseData().then((_) {
          // This will be handled by the _refreshPulseData method
        });
        return;
      }

      // First, move the camera immediately to the pulse location
      controller.moveCamera(
        CameraUpdate.newLatLng(pulseLocation),
      );

      // Then, ensure the map is centered on the pulse location with a slight delay
      // This helps ensure the map is fully loaded before animation
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          controller
              .animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: pulseLocation,
                zoom: 15.0,
              ),
            ),
          )
              .then((_) {
            // After animation is complete, mark the map as initialized
            if (mounted) {
              setState(() {
                _isMapInitialized = true;
              });
            }
          });
        }
      });

      // Set up a listener for the "My Location" button
      // This is a workaround since there's no direct callback for the button
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          // Add a marker for the pulse location again to ensure it's visible
          _setupMapElements();

          // Force the camera to focus on the pulse location one more time
          // This helps in case the map has shifted to the user's location
          _animateToPosition(pulseLocation);
        }
      });
    }
  }

  // Method to handle the "My Location" button click
  // This is called indirectly through onCameraMove
  void _handleMyLocationButtonClick() {
    // Check if we've already shown the snackbar recently
    final now = DateTime.now();
    final shouldShowSnackbar = _lastSnackbarTime == null ||
        now.difference(_lastSnackbarTime!).inSeconds >
            5; // Only show every 5 seconds at most

    // If we're already viewing the user's location or have shown the snackbar recently, don't show it again
    if (_isViewingUserLocation || !shouldShowSnackbar) {
      return;
    }

    // Set the flag to indicate we're viewing the user's location
    setState(() {
      _isViewingUserLocation = true;
      _hasShownLocationSnackbar = true;
      _lastSnackbarTime = now;
    });

    // Wait a moment for the camera to move to the user's location
    // Then offer a snackbar to return to the pulse location
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        // Hide any existing snackbars
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        // Show the snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Viewing your current location'),
            action: SnackBarAction(
              label: 'Return to Pulse',
              onPressed: () {
                _animateToPosition(widget.pulse.location);
                // Reset the flag when returning to pulse location
                setState(() {
                  _isViewingUserLocation = false;
                });
              },
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
  }

  // Calculate the distance between two LatLng points in kilometers
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371.0; // Earth's radius in kilometers

    // Convert latitude and longitude from degrees to radians
    final double lat1 = _degreesToRadians(point1.latitude);
    final double lon1 = _degreesToRadians(point1.longitude);
    final double lat2 = _degreesToRadians(point2.latitude);
    final double lon2 = _degreesToRadians(point2.longitude);

    // Haversine formula
    final double dLat = lat2 - lat1;
    final double dLon = lon2 - lon1;
    final double a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final double distance = earthRadius * c;

    return distance;
  }

  // Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }

  Future<void> _joinPulse() async {
    setState(() {
      _isJoining = true;
    });

    try {
      final supabaseService = Provider.of<SupabaseService>(
        context,
        listen: false,
      );
      await supabaseService.joinPulse(widget.pulse.id);

      setState(() {
        _hasJoined = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully joined pulse')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error joining pulse: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  Future<void> _leavePulse() async {
    setState(() {
      _isLeaving = true;
    });

    try {
      final supabaseService = Provider.of<SupabaseService>(
        context,
        listen: false,
      );
      await supabaseService.leavePulse(widget.pulse.id);

      setState(() {
        _hasJoined = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully left pulse')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error leaving pulse: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLeaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    final startDate = dateFormat.format(widget.pulse.startTime);
    final startTime = timeFormat.format(widget.pulse.startTime);
    final endTime = timeFormat.format(widget.pulse.endTime);

    final isCreator =
        Provider.of<SupabaseService>(context, listen: false).currentUserId ==
            widget.pulse.creatorId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pulse Details'),
        actions: [
          if (isCreator)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                // Navigate to edit pulse screen
                // Not implemented in this version
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Map showing pulse location
            Container(
              height: 250,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(12)),
                child: Stack(
                  children: [
                    // Google Map
                    GoogleMap(
                      // Use the pulse location directly for the initial camera position
                      // If the location is (0,0), we'll update it after fetching the pulse
                      initialCameraPosition: CameraPosition(
                        target: widget.pulse.location.latitude == 0 &&
                                widget.pulse.location.longitude == 0
                            ? const LatLng(37.7749,
                                -122.4194) // Default to San Francisco as a fallback
                            : widget.pulse.location,
                        zoom: 15.0,
                      ),
                      markers: _markers,
                      circles: _circles,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      mapToolbarEnabled: false,
                      zoomControlsEnabled: true,
                      compassEnabled: true,
                      onMapCreated: _onMapCreated,
                      mapType: MapType.normal,
                      // Handle camera movement
                      onCameraMove: (CameraPosition position) {
                        // Check if the camera has moved significantly away from the pulse location
                        // This could indicate the user pressed the "My Location" button
                        if (_isMapInitialized) {
                          final distanceFromPulse = _calculateDistance(
                              position.target, widget.pulse.location);

                          // If we've moved far from the pulse (likely to user location)
                          if (distanceFromPulse > 1.0) {
                            // > 1 km away
                            // Only call _handleMyLocationButtonClick if we're not already viewing user location
                            if (!_isViewingUserLocation) {
                              _handleMyLocationButtonClick();
                            }
                          } else {
                            // We're back near the pulse location
                            if (_isViewingUserLocation) {
                              setState(() {
                                _isViewingUserLocation = false;
                              });
                            }
                          }
                        }
                      },
                      // Add padding to ensure the marker is visible
                      padding: const EdgeInsets.only(bottom: 10),
                      // Ensure the map is interactive
                      rotateGesturesEnabled: true,
                      scrollGesturesEnabled: true,
                      zoomGesturesEnabled: true,
                      tiltGesturesEnabled: true,
                    ),

                    // Loading indicator while map is initializing
                    if (!_mapReady)
                      const Center(
                        child: CircularProgressIndicator(),
                      ),

                    // Pulse indicator animation
                    if (_mapReady)
                      Positioned.fill(
                        child: Center(
                          child: _PulsingCircle(
                            color: Colors.red.withAlpha(153),
                          ),
                        ),
                      ),

                    // "Center on Pulse" button
                    Positioned(
                      right: 16,
                      bottom: 100,
                      child: FloatingActionButton.small(
                        heroTag: 'center_on_pulse',
                        onPressed: () {
                          // Reset the user location flag and animate to pulse location
                          setState(() {
                            _isViewingUserLocation = false;
                          });
                          _animateToPosition(widget.pulse.location);
                        },
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue,
                        tooltip: 'Center on Pulse',
                        child: const Icon(Icons.center_focus_strong),
                      ),
                    ),

                    // Additional "Return to Pulse" button at the top
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  Colors.black.withAlpha(51), // 0.2 * 255 = 51
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              // Reset the user location flag and animate to pulse location
                              setState(() {
                                _isViewingUserLocation = false;
                              });
                              _animateToPosition(widget.pulse.location);
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_on,
                                      color: Colors.red, size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    'Show Pulse Location',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title with emoji
                  Row(
                    children: [
                      if (widget.pulse.activityEmoji != null) ...[
                        Text(
                          widget.pulse.activityEmoji!,
                          style: const TextStyle(fontSize: 32),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          widget.pulse.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Creator info
                  Row(
                    children: [
                      const Icon(Icons.person, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Created by ${widget.pulse.creatorName ?? 'Unknown'}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Date and time
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '$startDate\n$startTime - $endTime',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Participants
                  Row(
                    children: [
                      const Icon(Icons.people, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        widget.pulse.maxParticipants != null
                            ? '${widget.pulse.participantCount}/${widget.pulse.maxParticipants} participants'
                            : '${widget.pulse.participantCount} participants',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Description
                  const Text(
                    'Description',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(widget.pulse.description),
                  const SizedBox(height: 24),
                  // Join/Leave button
                  SizedBox(
                    width: double.infinity,
                    child: _hasJoined
                        ? ElevatedButton.icon(
                            onPressed: _isLeaving ? null : _leavePulse,
                            icon: _isLeaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.exit_to_app),
                            label: const Text('Leave Pulse'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: _isJoining ? null : _joinPulse,
                            icon: _isJoining
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.group_add),
                            label: const Text('Join Pulse'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  // Chat button (only if joined)
                  if (_hasJoined)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  PulseChatScreen(pulse: widget.pulse),
                            ),
                          );
                        },
                        icon: const Icon(Icons.chat),
                        label: const Text('Open Chat'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A widget that creates a pulsing circle animation
class _PulsingCircle extends StatefulWidget {
  final Color color;

  const _PulsingCircle({
    required this.color,
  });

  @override
  State<_PulsingCircle> createState() => _PulsingCircleState();
}

class _PulsingCircleState extends State<_PulsingCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
  }

  void _setupAnimation() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    // Start the animation and make it repeat
    if (!_isDisposed) {
      _animationController.repeat();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulsing circle
            Container(
              width: 60.0 * _animation.value,
              height: 60.0 * _animation.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withAlpha(
                  (255 * (1.0 - _animation.value)).toInt(),
                ),
              ),
            ),
            // Middle pulsing circle
            Container(
              width: 30.0 * (1.0 - (_animation.value * 0.5)),
              height: 30.0 * (1.0 - (_animation.value * 0.5)),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withAlpha(
                  (200 * (1.0 - _animation.value)).toInt(),
                ),
              ),
            ),
            // Inner static circle
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withAlpha(100),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
