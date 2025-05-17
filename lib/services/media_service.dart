import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_compress/video_compress.dart';
import 'package:pulsemeet/models/chat_message.dart';

/// A service for handling media uploads and downloads
class MediaService {
  static final MediaService _instance = MediaService._internal();
  
  factory MediaService() => _instance;
  
  MediaService._internal();
  
  final ImagePicker _imagePicker = ImagePicker();
  final Uuid _uuid = const Uuid();
  final SupabaseClient _supabase = Supabase.instance.client;
  
  /// Pick an image from the gallery
  Future<File?> pickImageFromGallery() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      
      if (pickedFile == null) return null;
      
      return File(pickedFile.path);
    } catch (e) {
      debugPrint('Error picking image from gallery: $e');
      return null;
    }
  }
  
  /// Take a photo with the camera
  Future<File?> takePhoto() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      
      if (pickedFile == null) return null;
      
      return File(pickedFile.path);
    } catch (e) {
      debugPrint('Error taking photo: $e');
      return null;
    }
  }
  
  /// Pick a video from the gallery
  Future<File?> pickVideoFromGallery() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );
      
      if (pickedFile == null) return null;
      
      return File(pickedFile.path);
    } catch (e) {
      debugPrint('Error picking video from gallery: $e');
      return null;
    }
  }
  
  /// Record a video with the camera
  Future<File?> recordVideo() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 1),
      );
      
      if (pickedFile == null) return null;
      
      return File(pickedFile.path);
    } catch (e) {
      debugPrint('Error recording video: $e');
      return null;
    }
  }
  
  /// Compress a video file
  Future<File?> compressVideo(File videoFile) async {
    try {
      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        videoFile.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      
      if (mediaInfo?.file == null) return null;
      
      return mediaInfo!.file!;
    } catch (e) {
      debugPrint('Error compressing video: $e');
      return null;
    }
  }
  
  /// Generate a thumbnail from a video file
  Future<File?> generateVideoThumbnail(File videoFile) async {
    try {
      final thumbnailBytes = await VideoCompress.getByteThumbnail(
        videoFile.path,
        quality: 50,
        position: -1,
      );
      
      if (thumbnailBytes == null) return null;
      
      final tempDir = await getTemporaryDirectory();
      final thumbnailPath = '${tempDir.path}/${_uuid.v4()}.jpg';
      final thumbnailFile = File(thumbnailPath);
      await thumbnailFile.writeAsBytes(thumbnailBytes);
      
      return thumbnailFile;
    } catch (e) {
      debugPrint('Error generating video thumbnail: $e');
      return null;
    }
  }
  
  /// Upload a media file to Supabase storage
  Future<MediaData?> uploadMedia(File file, String pulseId) async {
    try {
      final String fileName = '${_uuid.v4()}${path.extension(file.path)}';
      final String filePath = 'pulse_$pulseId/$fileName';
      
      // Determine mime type
      final String mimeType = _getMimeType(file.path);
      final bool isVideo = mimeType.startsWith('video/');
      
      // Compress video if needed
      File fileToUpload = file;
      File? thumbnailFile;
      
      if (isVideo) {
        // Compress video
        final compressedVideo = await compressVideo(file);
        if (compressedVideo != null) {
          fileToUpload = compressedVideo;
        }
        
        // Generate thumbnail
        thumbnailFile = await generateVideoThumbnail(fileToUpload);
      }
      
      // Upload the file
      await _supabase.storage.from('pulse_media').upload(
        filePath,
        fileToUpload,
        fileOptions: FileOptions(
          contentType: mimeType,
          upsert: true,
        ),
      );
      
      // Get the public URL
      final String fileUrl = _supabase.storage.from('pulse_media').getPublicUrl(filePath);
      
      // Upload thumbnail if it's a video
      String? thumbnailUrl;
      if (isVideo && thumbnailFile != null) {
        final String thumbnailFileName = '${_uuid.v4()}_thumb.jpg';
        final String thumbnailPath = 'pulse_$pulseId/$thumbnailFileName';
        
        await _supabase.storage.from('pulse_media').upload(
          thumbnailPath,
          thumbnailFile,
          fileOptions: FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
        
        thumbnailUrl = _supabase.storage.from('pulse_media').getPublicUrl(thumbnailPath);
      }
      
      // Get file size and dimensions
      final int fileSize = await fileToUpload.length();
      int? width, height, duration;
      
      if (isVideo) {
        final mediaInfo = await VideoCompress.getMediaInfo(fileToUpload.path);
        width = mediaInfo.width;
        height = mediaInfo.height;
        duration = mediaInfo.duration?.toInt();
      } else {
        // For images, we could use image package to get dimensions
        // This is simplified for now
        width = 800;
        height = 600;
      }
      
      // Create MediaData object
      return MediaData(
        url: fileUrl,
        thumbnailUrl: thumbnailUrl,
        mimeType: mimeType,
        size: fileSize,
        width: width,
        height: height,
        duration: duration,
      );
    } catch (e) {
      debugPrint('Error uploading media: $e');
      return null;
    }
  }
  
  /// Download a media file from a URL
  Future<File?> downloadMedia(String url, String fileName) async {
    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final Directory appDocDir = await getApplicationDocumentsDirectory();
        final String filePath = '${appDocDir.path}/$fileName';
        final File file = File(filePath);
        
        await file.writeAsBytes(response.bodyBytes);
        return file;
      } else {
        debugPrint('Error downloading media: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error downloading media: $e');
      return null;
    }
  }
  
  /// Get the mime type of a file based on its extension
  String _getMimeType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    
    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.avi':
        return 'video/x-msvideo';
      default:
        return 'application/octet-stream';
    }
  }
  
  /// Clear the cache
  Future<void> clearCache() async {
    try {
      await VideoCompress.deleteAllCache();
      
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        tempDir.listSync().forEach((entity) {
          if (entity is File) {
            entity.deleteSync();
          }
        });
      }
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }
}
