import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/supabase_service.dart';

/// Screen for managing privacy settings
class PrivacySettingsScreen extends StatefulWidget {
  final Profile profile;

  const PrivacySettingsScreen({
    super.key,
    required this.profile,
  });

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  late PrivacySettings _settings;
  bool _isLoading = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    // Create a copy of the settings to work with
    _settings = widget.profile.privacySettings;
  }

  /// Save privacy settings
  Future<void> _saveSettings() async {
    if (!_hasChanges) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final supabaseService =
          Provider.of<SupabaseService>(context, listen: false);

      await supabaseService.updatePrivacySettings(
        widget.profile.id,
        _settings,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Privacy settings saved')),
        );
        setState(() {
          _isLoading = false;
          _hasChanges = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving settings: ${e.toString()}')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _confirmDiscard,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Privacy Settings'),
          actions: [
            if (_hasChanges)
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _isLoading ? null : _saveSettings,
                tooltip: 'Save',
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'Manage your privacy preferences',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Show Online Status'),
                    subtitle: const Text(
                        'Allow others to see when you are online'),
                    value: _settings.showOnlineStatus,
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(
                          showOnlineStatus: value,
                        );
                        _hasChanges = true;
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Show Last Seen'),
                    subtitle: const Text(
                        'Allow others to see when you were last active'),
                    value: _settings.showLastSeen,
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(
                          showLastSeen: value,
                        );
                        _hasChanges = true;
                      });
                    },
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Show Profile to Non-Participants'),
                    subtitle: const Text(
                        'Allow users who are not in your pulses to view your profile'),
                    value: _settings.showProfileToNonParticipants,
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(
                          showProfileToNonParticipants: value,
                        );
                        _hasChanges = true;
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Allow Messages from Non-Participants'),
                    subtitle: const Text(
                        'Allow users who are not in your pulses to message you'),
                    value: _settings.allowMessagesFromNonParticipants,
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(
                          allowMessagesFromNonParticipants: value,
                        );
                        _hasChanges = true;
                      });
                    },
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Share Location with Participants'),
                    subtitle: const Text(
                        'Allow pulse participants to see your location'),
                    value: _settings.shareLocationWithParticipants,
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(
                          shareLocationWithParticipants: value,
                        );
                        _hasChanges = true;
                      });
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 16.0, top: 16.0),
                    child: Text(
                      'Location Sharing Mode',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  RadioListTile<LocationSharingMode>(
                    title: const Text('Always'),
                    subtitle: const Text(
                        'Share your location even when the app is in the background'),
                    value: LocationSharingMode.always,
                    groupValue: _settings.locationSharingMode,
                    onChanged: _settings.shareLocationWithParticipants
                        ? (value) {
                            if (value == null) return;
                            setState(() {
                              _settings = _settings.copyWith(
                                locationSharingMode: value,
                              );
                              _hasChanges = true;
                            });
                          }
                        : null,
                  ),
                  RadioListTile<LocationSharingMode>(
                    title: const Text('While Active'),
                    subtitle: const Text(
                        'Share your location only when you are actively using the app'),
                    value: LocationSharingMode.whileActive,
                    groupValue: _settings.locationSharingMode,
                    onChanged: _settings.shareLocationWithParticipants
                        ? (value) {
                            if (value == null) return;
                            setState(() {
                              _settings = _settings.copyWith(
                                locationSharingMode: value,
                              );
                              _hasChanges = true;
                            });
                          }
                        : null,
                  ),
                  RadioListTile<LocationSharingMode>(
                    title: const Text('Never'),
                    subtitle: const Text('Never share your location'),
                    value: LocationSharingMode.never,
                    groupValue: _settings.locationSharingMode,
                    onChanged: _settings.shareLocationWithParticipants
                        ? (value) {
                            if (value == null) return;
                            setState(() {
                              _settings = _settings.copyWith(
                                locationSharingMode: value,
                              );
                              _hasChanges = true;
                            });
                          }
                        : null,
                  ),
                  if (_hasChanges)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: FilledButton(
                        onPressed: _isLoading ? null : _saveSettings,
                        child: const Text('SAVE CHANGES'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
