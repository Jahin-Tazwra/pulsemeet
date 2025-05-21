import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/supabase_service.dart';
import 'package:provider/provider.dart';

/// A widget that displays a user avatar
class UserAvatar extends StatefulWidget {
  final String userId;
  final String? avatarUrl;
  final double size;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    required this.userId,
    this.avatarUrl,
    this.size = 40,
    this.onTap,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  Profile? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (widget.avatarUrl != null) {
      // If avatar URL is provided, we don't need to load the profile
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      final profile = await supabaseService.getProfile(widget.userId);
      
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _isLoading
            ? _buildLoadingAvatar()
            : _buildAvatar(),
      ),
    );
  }

  Widget _buildLoadingAvatar() {
    return CircleAvatar(
      radius: widget.size / 2,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: SizedBox(
        width: widget.size / 3,
        height: widget.size / 3,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    // Use provided avatar URL or get it from the profile
    final avatarUrl = widget.avatarUrl ?? _profile?.avatarUrl;
    
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: widget.size / 2,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: avatarUrl,
            fit: BoxFit.cover,
            width: widget.size,
            height: widget.size,
            placeholder: (context, url) => SizedBox(
              width: widget.size / 3,
              height: widget.size / 3,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            errorWidget: (context, url, error) => _buildFallbackAvatar(),
          ),
        ),
      );
    } else {
      return _buildFallbackAvatar();
    }
  }

  Widget _buildFallbackAvatar() {
    // Get initial from profile or use a fallback
    final String initial = _profile?.displayName?.isNotEmpty == true
        ? _profile!.displayName![0].toUpperCase()
        : (_profile?.username?.isNotEmpty == true
            ? _profile!.username![0].toUpperCase()
            : '?');
    
    return CircleAvatar(
      radius: widget.size / 2,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: widget.size / 2,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }
}
