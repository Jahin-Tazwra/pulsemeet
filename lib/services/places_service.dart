import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pulsemeet/config/env_config.dart';

/// A model class for place predictions from Google Places API
class PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final structuredFormatting = json['structured_formatting'] ?? {};
    return PlacePrediction(
      placeId: json['place_id'] ?? '',
      description: json['description'] ?? '',
      mainText: structuredFormatting['main_text'] ?? '',
      secondaryText: structuredFormatting['secondary_text'] ?? '',
    );
  }
}

/// A model class for place details from Google Places API
class PlaceDetails {
  final String placeId;
  final String name;
  final String address;
  final LatLng location;

  PlaceDetails({
    required this.placeId,
    required this.name,
    required this.address,
    required this.location,
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    final result = json['result'] ?? {};
    final geometry = result['geometry'] ?? {};
    final location = geometry['location'] ?? {};
    
    return PlaceDetails(
      placeId: result['place_id'] ?? '',
      name: result['name'] ?? '',
      address: result['formatted_address'] ?? '',
      location: LatLng(
        location['lat'] ?? 0.0,
        location['lng'] ?? 0.0,
      ),
    );
  }
}

/// A service class for Google Places API
class PlacesService {
  static final PlacesService _instance = PlacesService._internal();
  
  factory PlacesService() => _instance;
  
  PlacesService._internal();
  
  final String _baseUrl = 'https://maps.googleapis.com/maps/api/place';
  
  /// Get place predictions based on input text
  Future<List<PlacePrediction>> getPlacePredictions(String input) async {
    if (input.isEmpty) return [];
    
    try {
      final apiKey = EnvConfig.googleMapsApiKey;
      if (apiKey.isEmpty) {
        debugPrint('Google Maps API key is empty');
        return [];
      }
      
      final url = Uri.parse(
        '$_baseUrl/autocomplete/json?input=$input&key=$apiKey&components=country:us'
      );
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List;
          return predictions
              .map((prediction) => PlacePrediction.fromJson(prediction))
              .toList();
        } else {
          debugPrint('Error fetching place predictions: ${data['status']}');
          return [];
        }
      } else {
        debugPrint('Error fetching place predictions: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Error fetching place predictions: $e');
      return [];
    }
  }
  
  /// Get place details based on place ID
  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    if (placeId.isEmpty) return null;
    
    try {
      final apiKey = EnvConfig.googleMapsApiKey;
      if (apiKey.isEmpty) {
        debugPrint('Google Maps API key is empty');
        return null;
      }
      
      final url = Uri.parse(
        '$_baseUrl/details/json?place_id=$placeId&key=$apiKey&fields=place_id,name,formatted_address,geometry'
      );
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          return PlaceDetails.fromJson(data);
        } else {
          debugPrint('Error fetching place details: ${data['status']}');
          return null;
        }
      } else {
        debugPrint('Error fetching place details: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching place details: $e');
      return null;
    }
  }
}
