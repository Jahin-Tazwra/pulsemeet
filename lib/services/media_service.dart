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
import 'package:pulsemeet/models/message.dart';
import 'package:pulsemeet/models/encryption_key.dart';
import 'package:pulsemeet/services/encrypted_message_service.dart';

/// A service for handling media uploads and downloads
class MediaService {
  static final MediaService _instance = MediaService._internal();

  factory MediaService() => _instance;

  MediaService._internal();

  final ImagePicker _imagePicker = ImagePicker();
  final Uuid _uuid = const Uuid();
  final SupabaseClient _supabase = Supabase.instance.client;
  final EncryptedMessageService _encryptedMessageService =
      EncryptedMessageService();

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

  /// Upload a media file to Supabase storage with optional encryption
  Future<MediaData?> uploadMedia(
    File file,
    String conversationId, {
    ConversationType conversationType = ConversationType.pulse,
    bool enableEncryption = true,
  }) async {
    try {
      final String fileName = '${_uuid.v4()}${path.extension(file.path)}';
      final String filePath =
          '${conversationType.name}_$conversationId/$fileName';

      // Determine mime type
      final String mimeType = _getMimeType(file.path);
      final bool isVideo = mimeType.startsWith('video/');
      final bool isAudio = mimeType.startsWith('audio/');

      debugPrint('File path: ${file.path}');
      debugPrint('Detected MIME type: $mimeType');
      debugPrint('Is audio: $isAudio');

      // Process video first (compress and generate thumbnail) before encryption
      File fileToUpload = file;
      File? thumbnailFile;
      String uploadMimeType = mimeType; // Store original MIME type

      if (isVideo) {
        // Compress video first
        final compressedVideo = await compressVideo(file);
        if (compressedVideo != null) {
          fileToUpload = compressedVideo;
        }

        // Generate thumbnail from the compressed video
        thumbnailFile = await generateVideoThumbnail(fileToUpload);
      }

      // Encrypt file if encryption is enabled (after video processing)
      if (enableEncryption) {
        debugPrint('Encrypting media file before upload');
        final encryptedFile = await _encryptedMessageService.encryptMediaFile(
          fileToUpload,
          conversationId,
          conversationType,
        );
        if (encryptedFile != null) {
          fileToUpload = encryptedFile;
          debugPrint('Media file encrypted successfully');
          // Keep original MIME type even for encrypted files
        } else {
          debugPrint('Failed to encrypt media file, uploading unencrypted');
        }
      }

      // Upload the file using original MIME type - use different buckets for different media types
      final bucketName = isAudio ? 'audio' : 'pulse_media';

      await _supabase.storage.from(bucketName).upload(
            filePath,
            fileToUpload,
            fileOptions: FileOptions(
              contentType: uploadMimeType,
              upsert: true,
            ),
          );

      // Get the public URL
      final String fileUrl =
          _supabase.storage.from(bucketName).getPublicUrl(filePath);

      // Upload thumbnail if it's a video
      String? thumbnailUrl;
      if (isVideo && thumbnailFile != null) {
        final String thumbnailFileName = '${_uuid.v4()}_thumb.jpg';
        final String thumbnailPath =
            '${conversationType.name}_$conversationId/$thumbnailFileName';

        await _supabase.storage.from('pulse_media').upload(
              thumbnailPath,
              thumbnailFile,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );

        thumbnailUrl =
            _supabase.storage.from('pulse_media').getPublicUrl(thumbnailPath);
      }

      // Get file size and dimensions
      final int fileSize = await fileToUpload.length();
      int? width, height, duration;

      // Skip metadata reading for encrypted files as they can't be read by metadata readers
      if (enableEncryption && fileToUpload != file) {
        // File is encrypted, use default values to avoid metadata reading errors
        if (isVideo) {
          width = 1920; // Default video width
          height = 1080; // Default video height
          duration = 30000; // Default 30 seconds in milliseconds
        } else {
          width = 1024; // Default image width
          height = 1024; // Default image height
        }
        debugPrint('Using default metadata for encrypted file');
      } else {
        // File is not encrypted, read actual metadata
        if (isVideo) {
          try {
            final mediaInfo =
                await VideoCompress.getMediaInfo(fileToUpload.path);
            width = mediaInfo.width;
            height = mediaInfo.height;
            duration = mediaInfo.duration?.toInt();
          } catch (e) {
            debugPrint('Error getting video metadata: $e');
            // Fallback to defaults
            width = 1920;
            height = 1080;
            duration = 30000;
          }
        } else {
          // For images, we could use image package to get dimensions
          // This is simplified for now
          width = 1024;
          height = 1024;
        }
      }

      // Create MediaData object
      return MediaData(
        url: fileUrl,
        thumbnailUrl: thumbnailUrl,
        mimeType: uploadMimeType, // Use original MIME type
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
      // Image types
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';

      // Video types
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.avi':
        return 'video/x-msvideo';
      case '.mkv':
        return 'video/x-matroska';
      case '.webm':
        return 'video/webm';

      // Audio types
      case '.mp3':
        return 'audio/mp3';
      case '.m4a':
        return 'audio/aac'; // Use audio/aac for M4A files for Supabase compatibility
      case '.aac':
        return 'audio/aac';
      case '.wav':
        return 'audio/wav';
      case '.ogg':
        return 'audio/ogg';
      case '.flac':
        return 'audio/flac';

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

  /// Download and cache a media file with optional decryption
  Future<File?> downloadAndCacheMedia(
    String url, {
    String? conversationId,
    ConversationType? conversationType,
    bool isEncrypted = false,
  }) async {
    try {
      debugPrint('📥 Downloading media: $url (encrypted: $isEncrypted)');

      // Check if file is already cached
      final String fileName = url.split('/').last;
      final Directory cacheDir = await getTemporaryDirectory();
      final String cacheFileName =
          isEncrypted ? '${fileName}_decrypted' : fileName;
      final File cachedFile = File('${cacheDir.path}/$cacheFileName');

      // Check if cached file exists and is valid
      if (await cachedFile.exists()) {
        final fileSize = await cachedFile.length();
        if (fileSize > 0) {
          debugPrint(
              '📁 Using cached file: ${cachedFile.path} (${fileSize} bytes)');
          return cachedFile;
        } else {
          debugPrint('🗑️ Removing empty cached file: ${cachedFile.path}');
          await cachedFile.delete();
        }
      }

      // Download the file
      debugPrint('🌐 Downloading from URL: $url');
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        debugPrint('✅ Download successful: ${response.bodyBytes.length} bytes');

        if (isEncrypted && conversationId != null && conversationType != null) {
          // Save encrypted file temporarily with unique name to avoid conflicts
          final String encryptedFileName =
              '${_uuid.v4()}_${fileName}_encrypted';
          final File encryptedFile =
              File('${cacheDir.path}/$encryptedFileName');

          try {
            await encryptedFile.writeAsBytes(response.bodyBytes);
            debugPrint('💾 Saved encrypted file: ${encryptedFile.path}');

            // Verify encrypted file was written correctly
            if (!await encryptedFile.exists()) {
              debugPrint('❌ Encrypted file was not saved properly');
              return null;
            }

            final encryptedFileSize = await encryptedFile.length();
            if (encryptedFileSize == 0) {
              debugPrint('❌ Encrypted file is empty');
              await encryptedFile.delete();
              return null;
            }

            debugPrint('🔓 Starting decryption process...');
            // Decrypt the file
            final File? decryptedFile =
                await _encryptedMessageService.decryptMediaFile(
              encryptedFile,
              conversationId,
              conversationType,
            );

            if (decryptedFile != null && await decryptedFile.exists()) {
              final decryptedFileSize = await decryptedFile.length();
              debugPrint(
                  '✅ Decryption successful: ${decryptedFile.path} (${decryptedFileSize} bytes)');

              // Verify decrypted file is valid
              if (decryptedFileSize > 0) {
                // Move decrypted file to cache location
                await decryptedFile.copy(cachedFile.path);
                debugPrint('📁 Cached decrypted file: ${cachedFile.path}');

                // Clean up temporary files
                await decryptedFile.delete();
                await encryptedFile.delete();

                return cachedFile;
              } else {
                debugPrint('❌ Decrypted file is empty');
                await decryptedFile.delete();
              }
            } else {
              debugPrint('❌ Decryption failed or file does not exist');
            }

            // Clean up encrypted file on failure
            await encryptedFile.delete();
            return null;
          } catch (decryptionError) {
            debugPrint('❌ Error during decryption process: $decryptionError');
            // Clean up encrypted file on error
            if (await encryptedFile.exists()) {
              await encryptedFile.delete();
            }
            return null;
          }
        } else {
          // Save unencrypted file directly
          await cachedFile.writeAsBytes(response.bodyBytes);
          debugPrint('📁 Cached unencrypted file: ${cachedFile.path}');
          return cachedFile;
        }
      } else {
        debugPrint('❌ Download failed with status: ${response.statusCode}');
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error downloading media: $e');
      return null;
    }
  }

  /// Get decrypted media URL for display
  Future<String?> getDecryptedMediaUrl(
    MediaData mediaData,
    String conversationId,
    ConversationType conversationType,
  ) async {
    try {
      debugPrint('🎯 Getting decrypted media URL for: ${mediaData.url}');

      // If it's a local file, return as-is
      if (mediaData.url.startsWith('file://')) {
        debugPrint('📁 Local file detected, returning as-is');
        return mediaData.url;
      }

      // Check if this is an encrypted media file
      // For now, we'll assume all remote media in encrypted conversations is encrypted
      debugPrint('🔐 Attempting to decrypt remote media file');
      final File? decryptedFile = await downloadAndCacheMedia(
        mediaData.url,
        conversationId: conversationId,
        conversationType: conversationType,
        isEncrypted: true, // Assume encrypted for now
      );

      if (decryptedFile != null && await decryptedFile.exists()) {
        final fileSize = await decryptedFile.length();
        debugPrint(
            '✅ Decrypted media URL ready: file://${decryptedFile.path} ($fileSize bytes)');
        return 'file://${decryptedFile.path}';
      }

      debugPrint(
          '❌ Failed to get decrypted media file, falling back to original URL');
      // Fallback to original URL if decryption fails
      return mediaData.url;
    } catch (e) {
      debugPrint('❌ Error getting decrypted media URL: $e');
      return mediaData.url;
    }
  }
}
