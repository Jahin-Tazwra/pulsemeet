import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/services/database_initialization_service.dart';

Future<void> main() async {
  try {
    // Load environment variables
    await dotenv.load(fileName: '.env');
    
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
    
    if (supabaseUrl == null || supabaseAnonKey == null) {
      print('Error: Missing Supabase configuration in .env file');
      exit(1);
    }
    
    // Initialize Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    
    print('Initializing database...');
    
    // Initialize database
    final dbService = DatabaseInitializationService();
    await dbService.initialize();
    
    print('Database initialization completed successfully!');
    exit(0);
  } catch (e) {
    print('Error initializing database: $e');
    exit(1);
  }
}
