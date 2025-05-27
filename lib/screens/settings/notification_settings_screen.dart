import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../services/notification_preferences_service.dart';
import '../../services/firebase_messaging_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final NotificationPreferencesService _preferencesService =
      NotificationPreferencesService();
  final FirebaseMessagingService _firebaseMessaging =
      FirebaseMessagingService();

  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _showPreview = true;
  bool _quietHoursEnabled = false;
  int _quietHoursStart = 22;
  int _quietHoursEnd = 8;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final preferences = await _preferencesService.getAllPreferences();
      setState(() {
        _notificationsEnabled = preferences['notifications_enabled'] ?? true;
        _soundEnabled = preferences['sound_enabled'] ?? true;
        _vibrationEnabled = preferences['vibration_enabled'] ?? true;
        _showPreview = preferences['show_preview'] ?? true;
        _quietHoursEnabled = preferences['quiet_hours_enabled'] ?? false;
        _quietHoursStart = preferences['quiet_hours_start'] ?? 22;
        _quietHoursEnd = preferences['quiet_hours_end'] ?? 8;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading notification preferences: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor:
            isDark ? const Color(0xFF121212) : const Color(0xFF1E88E5),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionHeader('General'),
                _buildNotificationToggle(),
                const SizedBox(height: 16),
                if (_notificationsEnabled) ...[
                  _buildSectionHeader('Notification Content'),
                  _buildPreviewToggle(),
                  const SizedBox(height: 16),
                  _buildSectionHeader('Sound & Vibration'),
                  _buildSoundToggle(),
                  _buildVibrationToggle(),
                  const SizedBox(height: 16),
                  _buildSectionHeader('Quiet Hours'),
                  _buildQuietHoursToggle(),
                  if (_quietHoursEnabled) ...[
                    _buildQuietHoursTimePickers(),
                  ],
                  const SizedBox(height: 16),
                ],
                _buildSectionHeader('Device Information'),
                _buildDeviceInfo(),
                const SizedBox(height: 16),
                _buildResetButton(),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : const Color(0xFF212121),
        ),
      ),
    );
  }

  Widget _buildNotificationToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF212121) : Colors.white,
      child: SwitchListTile(
        title: Text(
          'Enable Notifications',
          style:
              TextStyle(color: isDark ? Colors.white : const Color(0xFF212121)),
        ),
        subtitle: Text(
          'Receive push notifications for new messages',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600]),
        ),
        value: _notificationsEnabled,
        activeColor: const Color(0xFF1E88E5),
        onChanged: (value) async {
          setState(() => _notificationsEnabled = value);
          await _preferencesService.setNotificationsEnabled(value);

          if (value) {
            // Re-initialize Firebase messaging if enabling notifications
            await _firebaseMessaging.initialize();
          }
        },
      ),
    );
  }

  Widget _buildPreviewToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF212121) : Colors.white,
      child: SwitchListTile(
        title: Text(
          'Show Message Preview',
          style:
              TextStyle(color: isDark ? Colors.white : const Color(0xFF212121)),
        ),
        subtitle: Text(
          'Display message content in notifications',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600]),
        ),
        value: _showPreview,
        activeColor: const Color(0xFF1E88E5),
        onChanged: (value) async {
          setState(() => _showPreview = value);
          await _preferencesService.setShowMessagePreview(value);
        },
      ),
    );
  }

  Widget _buildSoundToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF212121) : Colors.white,
      child: SwitchListTile(
        title: Text(
          'Sound',
          style:
              TextStyle(color: isDark ? Colors.white : const Color(0xFF212121)),
        ),
        subtitle: Text(
          'Play sound for notifications',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600]),
        ),
        value: _soundEnabled,
        activeColor: const Color(0xFF1E88E5),
        onChanged: (value) async {
          setState(() => _soundEnabled = value);
          await _preferencesService.setSoundEnabled(value);
        },
      ),
    );
  }

  Widget _buildVibrationToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF212121) : Colors.white,
      child: SwitchListTile(
        title: Text(
          'Vibration',
          style:
              TextStyle(color: isDark ? Colors.white : const Color(0xFF212121)),
        ),
        subtitle: Text(
          'Vibrate for notifications',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600]),
        ),
        value: _vibrationEnabled,
        activeColor: const Color(0xFF1E88E5),
        onChanged: (value) async {
          setState(() => _vibrationEnabled = value);
          await _preferencesService.setVibrationEnabled(value);
        },
      ),
    );
  }

  Widget _buildQuietHoursToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF212121) : Colors.white,
      child: SwitchListTile(
        title: Text(
          'Quiet Hours',
          style:
              TextStyle(color: isDark ? Colors.white : const Color(0xFF212121)),
        ),
        subtitle: Text(
          'Disable notifications during specific hours',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600]),
        ),
        value: _quietHoursEnabled,
        activeColor: const Color(0xFF1E88E5),
        onChanged: (value) async {
          setState(() => _quietHoursEnabled = value);
          await _preferencesService.setQuietHoursEnabled(value);
        },
      ),
    );
  }

  Widget _buildQuietHoursTimePickers() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF212121) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Start Time',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xFF212121),
                  ),
                ),
                GestureDetector(
                  onTap: () => _selectTime(true),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF1E88E5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_quietHoursStart.toString().padLeft(2, '0')}:00',
                      style: const TextStyle(
                        color: Color(0xFF1E88E5),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'End Time',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xFF212121),
                  ),
                ),
                GestureDetector(
                  onTap: () => _selectTime(false),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF1E88E5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_quietHoursEnd.toString().padLeft(2, '0')}:00',
                      style: const TextStyle(
                        color: Color(0xFF1E88E5),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF212121) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Firebase Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF212121),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _firebaseMessaging.isInitialized
                      ? Icons.check_circle
                      : Icons.error,
                  color: _firebaseMessaging.isInitialized
                      ? Colors.green
                      : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _firebaseMessaging.isInitialized
                      ? 'Connected'
                      : 'Not Connected',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey[600],
                  ),
                ),
              ],
            ),
            if (_firebaseMessaging.fcmToken != null) ...[
              const SizedBox(height: 8),
              Text(
                'Device Token: ${_firebaseMessaging.fcmToken!.substring(0, 20)}...',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.grey[500],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return ElevatedButton(
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Reset Settings'),
            content: const Text(
                'Are you sure you want to reset all notification settings to defaults?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Reset'),
              ),
            ],
          ),
        );

        if (confirmed == true) {
          await _preferencesService.resetToDefaults();
          await _loadPreferences();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Settings reset to defaults')),
            );
          }
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      child: const Text('Reset to Defaults'),
    );
  }

  Future<void> _selectTime(bool isStartTime) async {
    final currentHour = isStartTime ? _quietHoursStart : _quietHoursEnd;

    final selectedHour = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select ${isStartTime ? 'Start' : 'End'} Time'),
        content: SizedBox(
          height: 200,
          child: CupertinoPicker(
            itemExtent: 40,
            scrollController:
                FixedExtentScrollController(initialItem: currentHour),
            onSelectedItemChanged: (index) {},
            children: List.generate(
                24,
                (index) => Center(
                      child: Text('${index.toString().padLeft(2, '0')}:00'),
                    )),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, currentHour),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (selectedHour != null) {
      setState(() {
        if (isStartTime) {
          _quietHoursStart = selectedHour;
        } else {
          _quietHoursEnd = selectedHour;
        }
      });

      if (isStartTime) {
        await _preferencesService.setQuietHoursStart(selectedHour);
      } else {
        await _preferencesService.setQuietHoursEnd(selectedHour);
      }
    }
  }
}
