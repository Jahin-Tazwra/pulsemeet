import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// A widget that displays the profile header with avatar and basic info
class ProfileHeader extends StatelessWidget {
  final Profile profile;
  final File? selectedImage;
  final VoidCallback? onAvatarTap;
  final bool isEditable;
  final bool isLoading;

  const ProfileHeader({
    super.key,
    required this.profile,
    this.selectedImage,
    this.onAvatarTap,
    this.isEditable = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Avatar with edit option
        Stack(
          children: [
            // Avatar
            GestureDetector(
              onTap: isEditable ? onAvatarTap : null,
              child: Hero(
                tag: 'profile-avatar-${profile.id}',
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primaryContainer,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(40),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _buildAvatarImage(context),
                  ),
                ),
              ),
            ),
            
            // Edit indicator
            if (isEditable)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.edit,
                    size: 16,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
              
            // Loading indicator
            if (isLoading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(100),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Display name
        Text(
          profile.displayName ?? 'No Name',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 4),
        
        // Username
        Text(
          profile.username != null ? '@${profile.username}' : 'No username',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
          textAlign: TextAlign.center,
        ),
        
        // Verification badge
        if (profile.isVerified)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Verified',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
  
  /// Build the avatar image based on the available sources
  Widget _buildAvatarImage(BuildContext context) {
    // If there's a selected image (during editing), show it
    if (selectedImage != null) {
      return Image.file(
        selectedImage!,
        fit: BoxFit.cover,
        width: 120,
        height: 120,
        errorBuilder: (context, error, stackTrace) => _buildFallbackAvatar(context),
      );
    }
    
    // If there's a remote avatar URL, show it
    if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: profile.avatarUrl!,
        fit: BoxFit.cover,
        width: 120,
        height: 120,
        placeholder: (context, url) => const Center(
          child: CircularProgressIndicator(),
        ),
        errorWidget: (context, url, error) => _buildFallbackAvatar(context),
      );
    }
    
    // Fallback to initials
    return _buildFallbackAvatar(context);
  }
  
  /// Build a fallback avatar with initials
  Widget _buildFallbackAvatar(BuildContext context) {
    final String initial = profile.displayName?.isNotEmpty == true
        ? profile.displayName![0].toUpperCase()
        : (profile.username?.isNotEmpty == true
            ? profile.username![0].toUpperCase()
            : '?');
            
    return Container(
      color: Theme.of(context).colorScheme.primary,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }
}
