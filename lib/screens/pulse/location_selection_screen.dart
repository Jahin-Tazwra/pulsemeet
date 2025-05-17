import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/screens/pulse/pulse_creation_screen.dart';
import 'package:pulsemeet/services/places_service.dart';

/// Screen for selecting a location on a full-screen map
class LocationSelectionScreen extends StatefulWidget {
  const LocationSelectionScreen({super.key});

  @override
  State<LocationSelectionScreen> createState() =>
      _LocationSelectionScreenState();
}

class _LocationSelectionScreenState extends State<LocationSelectionScreen> {
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  LatLng? _currentLocation;
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Set<Marker> _markers = {};

  // Places service and predictions
  final PlacesService _placesService = PlacesService();
  List<PlacePrediction> _predictions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();

    // Add listener to search controller for autocomplete
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _mapController?.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Handle search text changes with debounce
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_searchController.text.isNotEmpty) {
        _getPlacePredictions(_searchController.text);
      } else {
        setState(() {
          _predictions = [];
        });
      }
    });
  }

  /// Get place predictions from the Places API
  Future<void> _getPlacePredictions(String input) async {
    setState(() {
      _isSearching = true;
    });

    try {
      final predictions = await _placesService.getPlacePredictions(input);

      if (mounted) {
        setState(() {
          _predictions = predictions;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _predictions = [];
          _isSearching = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching place suggestions: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Get the user's current location
  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Get current position with high accuracy
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final location = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentLocation = location;
        // If no location is selected yet, use the current location
        if (_selectedLocation == null) {
          _selectedLocation = location;
          _updateMarkers();
        }
        _isLoading = false;
      });

      // Move camera to current location
      _animateToLocation(location);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: ${e.toString()}')),
        );
      }
    }
  }

  /// Update markers on the map
  void _updateMarkers() {
    if (_selectedLocation == null) return;

    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('selected_location'),
          position: _selectedLocation!,
          infoWindow: const InfoWindow(title: 'Selected Location'),
        ),
      };
    });
  }

  /// Animate the camera to a specific location
  void _animateToLocation(LatLng location) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: location,
          zoom: 15,
        ),
      ),
    );
  }

  /// Handle map tap to select location
  void _onMapTap(LatLng location) {
    setState(() {
      _selectedLocation = location;
      _updateMarkers();
    });
  }

  /// Handle map long press to select location
  void _onMapLongPress(LatLng location) {
    setState(() {
      _selectedLocation = location;
      _updateMarkers();
    });

    // Show a snackbar to confirm the selection
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Location selected'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// Handle search form submission
  void _handleSearch() {
    final searchQuery = _searchController.text.trim();
    if (searchQuery.isEmpty) return;

    // If we already have predictions, select the first one
    if (_predictions.isNotEmpty) {
      _selectPlace(_predictions.first);
    } else {
      // Otherwise, get predictions
      _getPlacePredictions(searchQuery);
    }
  }

  /// Handle place selection from predictions
  Future<void> _selectPlace(PlacePrediction prediction) async {
    setState(() {
      _isSearching = true;
      // Clear predictions to hide the dropdown
      _predictions = [];
    });

    try {
      // Get place details
      final placeDetails =
          await _placesService.getPlaceDetails(prediction.placeId);

      if (placeDetails != null && mounted) {
        // Update selected location
        setState(() {
          _selectedLocation = placeDetails.location;
          _updateMarkers();
          _isSearching = false;
        });

        // Update search text
        _searchController.text = placeDetails.name;

        // Animate to the selected location
        _animateToLocation(placeDetails.location);
      } else {
        if (mounted) {
          setState(() {
            _isSearching = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not get place details'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting place: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Navigate to the pulse creation screen with the selected location
  void _navigateToPulseCreation() {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location first'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PulseCreationScreen(location: _selectedLocation!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _selectedLocation ??
                  const LatLng(37.7749, -122.4194), // Default to San Francisco
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: true,
            markers: _markers,
            onTap: _onMapTap,
            onLongPress: _onMapLongPress,
            onMapCreated: (controller) {
              _mapController = controller;
              if (_selectedLocation != null) {
                _updateMarkers();
              }
            },
          ),

          // Search bar at the top with predictions dropdown
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // Search bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(60),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search for a place',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _isSearching
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                              },
                            ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    onSubmitted: (_) => _handleSearch(),
                  ),
                ),

                // Predictions dropdown
                if (_predictions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(60),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.3,
                    ),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _predictions.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final prediction = _predictions[index];
                        return ListTile(
                          title: Text(
                            prediction.mainText,
                            style: const TextStyle(fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            prediction.secondaryText,
                            style: const TextStyle(
                                fontSize: 14, color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          dense: true,
                          onTap: () => _selectPlace(prediction),
                          leading:
                              const Icon(Icons.location_on, color: Colors.grey),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Loading indicator
          if (_isLoading)
            Container(
              color: Colors.black.withAlpha(100),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),

          // Bottom buttons
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Use my location button
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: FloatingActionButton.extended(
                    heroTag: 'use_my_location',
                    onPressed: () {
                      if (_currentLocation != null) {
                        setState(() {
                          _selectedLocation = _currentLocation;
                          _updateMarkers();
                        });
                        _animateToLocation(_currentLocation!);
                      } else {
                        _getCurrentLocation();
                      }
                    },
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Use My Location'),
                  ),
                ),

                // Next button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedLocation != null
                        ? _navigateToPulseCreation
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Next',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
