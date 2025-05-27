import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/supabase_service.dart';
import 'package:provider/provider.dart';

/// A widget that displays a user avatar
class UserAvatar extends StatefulWidget {
  final String userId;
  final String? avatarUrl;
  final String? displayName; // Add display name for fallback
  final String? username; // Add username for fallback
  final double size;
  final VoidCallback? onTap;
  final bool skipProfileLoad; // Skip database call if we have all needed data

  const UserAvatar({
    super.key,
    required this.userId,
    this.avatarUrl,
    this.displayName,
    this.username,
    this.size = 40,
    this.onTap,
    this.skipProfileLoad = false,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  Profile? _profile;
  bool _isLoading = true;

  // Static cache for profile data to avoid repeated database calls
  static final Map<String, Profile?> _profileCache = {};

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    // OPTIMIZATION: If we have all needed data, don't make database call
    if (widget.avatarUrl != null &&
        (widget.displayName != null || widget.username != null)) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // FALLBACK: If skipProfileLoad is true but we don't have avatar URL, still load profile
    // This handles cases where older messages don't have avatar URLs stored
    if (widget.skipProfileLoad && widget.avatarUrl == null) {
      debugPrint(
          '🔄 UserAvatar: skipProfileLoad=true but avatarUrl=null, loading profile as fallback');
    }

    // OPTIMIZATION: Check cache first
    if (_profileCache.containsKey(widget.userId)) {
      setState(() {
        _profile = _profileCache[widget.userId];
        _isLoading = false;
      });
      return;
    }

    try {
      final supabaseService =
          Provider.of<SupabaseService>(context, listen: false);
      final profile = await supabaseService.getProfile(widget.userId);

      // Cache the result
      _profileCache[widget.userId] = profile;

      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Cache null result to avoid repeated failed calls
      _profileCache[widget.userId] = null;

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
        child: _isLoading ? _buildLoadingAvatar() : _buildAvatar(),
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
    // OPTIMIZATION: Use provided display name/username first, then profile, then fallback
    String initial = '?';

    if (widget.displayName?.isNotEmpty == true) {
      initial = widget.displayName![0].toUpperCase();
    } else if (widget.username?.isNotEmpty == true) {
      initial = widget.username![0].toUpperCase();
    } else if (_profile?.displayName?.isNotEmpty == true) {
      initial = _profile!.displayName![0].toUpperCase();
    } else if (_profile?.username?.isNotEmpty == true) {
      initial = _profile!.username![0].toUpperCase();
    }

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
