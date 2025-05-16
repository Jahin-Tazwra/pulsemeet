import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// This script updates the Google Maps API key in the AndroidManifest.xml file
/// Run this script with: dart scripts/update_maps_api_key.dart
void main() async {
  // Load environment variables
  await dotenv.load();
  
  // Get the Google Maps API key from .env
  final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Error: GOOGLE_MAPS_API_KEY not found in .env file');
    exit(1);
  }
  
  // Path to AndroidManifest.xml
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  
  try {
    // Read the manifest file
    final file = File(manifestPath);
    if (!file.existsSync()) {
      print('Error: AndroidManifest.xml not found at $manifestPath');
      exit(1);
    }
    
    String content = file.readAsStringSync();
    
    // Regular expression to find the Google Maps API key meta-data tag
    final regex = RegExp(
      r'<meta-data\s+android:name="com\.google\.android\.geo\.API_KEY"\s+android:value="[^"]*"\s*/>'
    );
    
    // New meta-data tag with the API key from .env
    final replacement = 
      '<meta-data\n            android:name="com.google.android.geo.API_KEY"\n            android:value="$apiKey" />';
    
    // Replace the API key
    if (regex.hasMatch(content)) {
      content = content.replaceAll(regex, replacement);
      file.writeAsStringSync(content);
      print('Successfully updated Google Maps API key in AndroidManifest.xml');
    } else {
      print('Warning: Google Maps API key meta-data tag not found in AndroidManifest.xml');
      print('Please add the following meta-data tag to your AndroidManifest.xml:');
      print(replacement);
    }
  } catch (e) {
    print('Error updating Google Maps API key: $e');
    exit(1);
  }
}
