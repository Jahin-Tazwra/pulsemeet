import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Script to fix the typing_status table schema
Future<void> main() async {
  try {
    // Load environment variables
    await dotenv.load(fileName: '.env');
    
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
    
    if (supabaseUrl == null || supabaseAnonKey == null) {
      print('❌ Missing Supabase configuration in .env file');
      exit(1);
    }
    
    // Initialize Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    
    final client = Supabase.instance.client;
    print('🔗 Connected to Supabase: $supabaseUrl');
    
    // Read the migration file
    final migrationFile = File('migrations/fix_typing_status_schema.sql');
    if (!await migrationFile.exists()) {
      print('❌ Migration file not found: ${migrationFile.path}');
      exit(1);
    }
    
    final migrationSql = await migrationFile.readAsString();
    print('📄 Loaded migration file: ${migrationFile.path}');
    
    // Execute the migration
    print('🚀 Executing typing status schema fix...');
    
    // Split the SQL into individual statements and execute them
    final statements = migrationSql
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.startsWith('--'))
        .toList();
    
    for (int i = 0; i < statements.length; i++) {
      final statement = statements[i];
      if (statement.isEmpty) continue;
      
      try {
        print('📝 Executing statement ${i + 1}/${statements.length}...');
        
        // Use RPC to execute raw SQL
        await client.rpc('exec_sql', params: {'sql': statement});
        print('✅ Statement ${i + 1} executed successfully');
      } catch (e) {
        print('⚠️ Statement ${i + 1} failed (may be expected): $e');
        // Continue with other statements
      }
    }
    
    // Test the new table
    print('🧪 Testing the new typing_status table...');
    try {
      final result = await client
          .from('typing_status')
          .select('id')
          .limit(1);
      print('✅ typing_status table is accessible');
    } catch (e) {
      print('❌ Failed to access typing_status table: $e');
    }
    
    print('🎉 Typing status schema fix completed!');
    
  } catch (e) {
    print('❌ Error fixing typing status schema: $e');
    exit(1);
  }
}
