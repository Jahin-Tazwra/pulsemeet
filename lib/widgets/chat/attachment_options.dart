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
                const Color(0xFF424242), // Dark grey
                onImageFromCamera,
              ),
              _buildOptionButton(
                context,
                Icons.photo,
                'Gallery',
                const Color(0xFF616161), // Medium-dark grey
                onImageFromGallery,
              ),
              _buildOptionButton(
                context,
                Icons.videocam,
                'Video',
                const Color(0xFF757575), // Medium grey
                onVideoFromCamera,
              ),
              _buildOptionButton(
                context,
                Icons.video_library,
                'Video Gallery',
                const Color(0xFF9E9E9E), // Medium-light grey
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
                const Color(0xFFBDBDBD), // Light grey
                onLocation,
              ),
              _buildOptionButton(
                context,
                Icons.location_searching,
                'Live Location',
                const Color(0xFFE0E0E0), // Very light grey
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
