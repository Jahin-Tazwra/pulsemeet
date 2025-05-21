import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/services/supabase_service.dart';

/// Screen for managing notification settings
class NotificationSettingsScreen extends StatefulWidget {
  final Profile profile;

  const NotificationSettingsScreen({
    super.key,
    required this.profile,
  });

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late NotificationSettings _settings;
  bool _isLoading = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    // Create a copy of the settings to work with
    _settings = widget.profile.notificationSettings;
  }

  /// Save notification settings
  Future<void> _saveSettings() async {
    if (!_hasChanges) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final supabaseService =
          Provider.of<SupabaseService>(context, listen: false);

      await supabaseService.updateNotificationSettings(
        widget.profile.id,
        _settings,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification settings saved')),
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
          title: const Text('Notification Settings'),
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
                      'Choose which notifications you want to receive',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Push Notifications'),
                    subtitle: const Text(
                        'Enable or disable all push notifications'),
                    value: _settings.pushNotifications,
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(
                          pushNotifications: value,
                        );
                        _hasChanges = true;
                      });
                    },
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('New Pulse Notifications'),
                    subtitle: const Text(
                        'Get notified when new pulses are created nearby'),
                    value: _settings.newPulseNotifications,
                    onChanged: _settings.pushNotifications
                        ? (value) {
                            setState(() {
                              _settings = _settings.copyWith(
                                newPulseNotifications: value,
                              );
                              _hasChanges = true;
                            });
                          }
                        : null,
                  ),
                  SwitchListTile(
                    title: const Text('Message Notifications'),
                    subtitle: const Text(
                        'Get notified when you receive new messages'),
                    value: _settings.messageNotifications,
                    onChanged: _settings.pushNotifications
                        ? (value) {
                            setState(() {
                              _settings = _settings.copyWith(
                                messageNotifications: value,
                              );
                              _hasChanges = true;
                            });
                          }
                        : null,
                  ),
                  SwitchListTile(
                    title: const Text('Mention Notifications'),
                    subtitle: const Text(
                        'Get notified when someone mentions you in a message'),
                    value: _settings.mentionNotifications,
                    onChanged: _settings.pushNotifications
                        ? (value) {
                            setState(() {
                              _settings = _settings.copyWith(
                                mentionNotifications: value,
                              );
                              _hasChanges = true;
                            });
                          }
                        : null,
                  ),
                  SwitchListTile(
                    title: const Text('Pulse Updates Notifications'),
                    subtitle: const Text(
                        'Get notified about updates to pulses you\'ve joined'),
                    value: _settings.pulseUpdatesNotifications,
                    onChanged: _settings.pushNotifications
                        ? (value) {
                            setState(() {
                              _settings = _settings.copyWith(
                                pulseUpdatesNotifications: value,
                              );
                              _hasChanges = true;
                            });
                          }
                        : null,
                  ),
                  SwitchListTile(
                    title: const Text('Nearby Pulses Notifications'),
                    subtitle: const Text(
                        'Get notified when you are near active pulses'),
                    value: _settings.nearbyPulsesNotifications,
                    onChanged: _settings.pushNotifications
                        ? (value) {
                            setState(() {
                              _settings = _settings.copyWith(
                                nearbyPulsesNotifications: value,
                              );
                              _hasChanges = true;
                            });
                          }
                        : null,
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Email Notifications'),
                    subtitle: const Text(
                        'Receive important notifications via email'),
                    value: _settings.emailNotifications,
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(
                          emailNotifications: value,
                        );
                        _hasChanges = true;
                      });
                    },
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
