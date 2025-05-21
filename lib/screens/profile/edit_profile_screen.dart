import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/supabase_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pulsemeet/widgets/profile/profile_header.dart';

/// Screen for editing user profile
class EditProfileScreen extends StatefulWidget {
  final Profile profile;

  const EditProfileScreen({
    super.key,
    required this.profile,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;
  late final TextEditingController _locationController;
  final List<String> _interests = [];

  bool _isLoading = false;
  bool _hasChanges = false;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.profile.username);
    _displayNameController =
        TextEditingController(text: widget.profile.displayName);
    _bioController = TextEditingController(text: widget.profile.bio);
    _locationController = TextEditingController(text: widget.profile.location);

    // Initialize interests
    if (widget.profile.interests.isNotEmpty) {
      _interests.addAll(widget.profile.interests);
    }

    // Add listeners to detect changes
    _usernameController.addListener(_onFieldChanged);
    _displayNameController.addListener(_onFieldChanged);
    _bioController.addListener(_onFieldChanged);
    _locationController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _usernameController.removeListener(_onFieldChanged);
    _displayNameController.removeListener(_onFieldChanged);
    _bioController.removeListener(_onFieldChanged);
    _locationController.removeListener(_onFieldChanged);

    _usernameController.dispose();
    _displayNameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  /// Called when any field changes to track if there are unsaved changes
  void _onFieldChanged() {
    final hasChanges = _usernameController.text != widget.profile.username ||
        _displayNameController.text != widget.profile.displayName ||
        _bioController.text != widget.profile.bio ||
        _locationController.text != widget.profile.location ||
        _selectedImage != null ||
        !_areListsEqual(_interests, widget.profile.interests);

    if (hasChanges != _hasChanges) {
      setState(() {
        _hasChanges = hasChanges;
      });
    }
  }

  /// Compare two lists for equality
  bool _areListsEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  /// Show image source selection dialog
  Future<void> _pickImage() async {
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _hasChanges = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: ${e.toString()}')),
        );
      }
    }
  }

  /// Add a new interest
  void _addInterest(String interest) {
    if (interest.isEmpty) return;
    if (_interests.contains(interest)) return;

    setState(() {
      _interests.add(interest);
      _hasChanges = true;
    });
  }

  /// Remove an interest
  void _removeInterest(String interest) {
    setState(() {
      _interests.remove(interest);
      _hasChanges = true;
    });
  }

  /// Show discard changes confirmation dialog
  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Changes?'),
        content: const Text(
            'You have unsaved changes. Are you sure you want to discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DISCARD'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// Save profile changes
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final supabaseService =
          Provider.of<SupabaseService>(context, listen: false);

      // Upload avatar if selected
      String? avatarUrl;
      if (_selectedImage != null) {
        avatarUrl = await supabaseService.uploadAvatar(
          widget.profile.id,
          _selectedImage!,
        );
      }

      // Update profile
      await supabaseService.upsertProfile(
        id: widget.profile.id,
        username: _usernameController.text,
        displayName: _displayNameController.text,
        bio: _bioController.text,
        avatarUrl: avatarUrl,
        location: _locationController.text,
        interests: _interests,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            if (!_hasChanges) {
              Navigator.of(context).pop();
              return;
            }

            final bool shouldPop = await _confirmDiscard();
            if (shouldPop && context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          if (_hasChanges)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isLoading ? null : _saveProfile,
              tooltip: 'Save',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar
                    ProfileHeader(
                      profile: widget.profile,
                      selectedImage: _selectedImage,
                      onAvatarTap: _pickImage,
                      isEditable: true,
                    ),
                    const SizedBox(height: 24),

                    // Username
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: 'Enter a unique username',
                        border: OutlineInputBorder(),
                        prefixText: '@',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a username';
                        }
                        if (value.contains(' ')) {
                          return 'Username cannot contain spaces';
                        }
                        if (value.length < 3) {
                          return 'Username must be at least 3 characters';
                        }
                        if (value.length > 30) {
                          return 'Username must be less than 30 characters';
                        }
                        final validUsernameRegex = RegExp(r'^[a-zA-Z0-9_\.]+$');
                        if (!validUsernameRegex.hasMatch(value)) {
                          return 'Username can only contain letters, numbers, underscores, and periods';
                        }
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),

                    // Display name
                    TextFormField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                        hintText: 'Enter your name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a display name';
                        }
                        if (value.length < 2) {
                          return 'Display name must be at least 2 characters';
                        }
                        if (value.length > 50) {
                          return 'Display name must be less than 50 characters';
                        }
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),

                    // Location
                    TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        hintText: 'City, Country',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),

                    // Bio
                    TextFormField(
                      controller: _bioController,
                      decoration: const InputDecoration(
                        labelText: 'Bio',
                        hintText: 'Tell others about yourself',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.info),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                      maxLength: 150,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 16),

                    // Interests
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Interests',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ..._interests.map((interest) => Chip(
                                      label: Text(interest),
                                      deleteIcon:
                                          const Icon(Icons.close, size: 16),
                                      onDeleted: () =>
                                          _removeInterest(interest),
                                    )),
                                ActionChip(
                                  avatar: const Icon(Icons.add, size: 16),
                                  label: const Text('Add Interest'),
                                  onPressed: () => _showAddInterestDialog(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _hasChanges ? _saveProfile : null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('SAVE PROFILE'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Show dialog to add a new interest
  Future<void> _showAddInterestDialog() async {
    final TextEditingController controller = TextEditingController();

    final String? interest = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Interest'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Interest',
            hintText: 'Enter an interest',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('ADD'),
          ),
        ],
      ),
    );

    if (interest != null && interest.isNotEmpty) {
      _addInterest(interest);
    }
  }
}
