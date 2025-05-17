import 'package:flutter/material.dart';

/// A widget that displays attachment options for the message input
class AttachmentOptions extends StatelessWidget {
  final VoidCallback onImageFromCamera;
  final VoidCallback onImageFromGallery;
  final VoidCallback onVideoFromCamera;
  final VoidCallback onVideoFromGallery;
  final VoidCallback onLocation;
  final VoidCallback onLiveLocation;

  const AttachmentOptions({
    super.key,
    required this.onImageFromCamera,
    required this.onImageFromGallery,
    required this.onVideoFromCamera,
    required this.onVideoFromGallery,
    required this.onLocation,
    required this.onLiveLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 16.0,
        horizontal: 8.0,
      ),
      color: Theme.of(context).cardColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildOptionButton(
                context,
                Icons.camera_alt,
                'Camera',
                Colors.purple,
                onImageFromCamera,
              ),
              _buildOptionButton(
                context,
                Icons.photo,
                'Gallery',
                Colors.pink,
                onImageFromGallery,
              ),
              _buildOptionButton(
                context,
                Icons.videocam,
                'Video',
                Colors.red,
                onVideoFromCamera,
              ),
              _buildOptionButton(
                context,
                Icons.video_library,
                'Video Gallery',
                Colors.orange,
                onVideoFromGallery,
              ),
            ],
          ),
          const SizedBox(height: 16.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildOptionButton(
                context,
                Icons.location_on,
                'Location',
                Colors.green,
                onLocation,
              ),
              _buildOptionButton(
                context,
                Icons.location_searching,
                'Live Location',
                Colors.blue,
                onLiveLocation,
              ),
              // Placeholder buttons to maintain alignment
              const SizedBox(width: 64.0),
              const SizedBox(width: 64.0),
            ],
          ),
        ],
      ),
    );
  }
  
  /// Build an option button
  Widget _buildOptionButton(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48.0,
            height: 48.0,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8.0),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.0,
            ),
          ),
        ],
      ),
    );
  }
}
