import 'package:flutter/material.dart';
import '../../utils/notification_test_helper.dart';
import '../../services/firebase_messaging_service.dart';

class NotificationTestScreen extends StatefulWidget {
  const NotificationTestScreen({super.key});

  @override
  State<NotificationTestScreen> createState() => _NotificationTestScreenState();
}

class _NotificationTestScreenState extends State<NotificationTestScreen> {
  bool _isRunningTests = false;
  Map<String, bool> _testResults = {};
  String _statusMessage = 'Ready to run tests';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification System Test'),
        backgroundColor:
            isDark ? const Color(0xFF121212) : const Color(0xFF1E88E5),
        foregroundColor: Colors.white,
      ),
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status Card
              Card(
                color: isDark ? const Color(0xFF212121) : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Test Status',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:
                              isDark ? Colors.white : const Color(0xFF212121),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusMessage,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                      if (_isRunningTests) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Test Results
              if (_testResults.isNotEmpty) ...[
                Card(
                  color: isDark ? const Color(0xFF212121) : Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Test Results',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color:
                                isDark ? Colors.white : const Color(0xFF212121),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ..._testResults.entries.map((entry) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    entry.value
                                        ? Icons.check_circle
                                        : Icons.error,
                                    color:
                                        entry.value ? Colors.green : Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _formatTestName(entry.key),
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF212121),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    entry.value ? 'PASS' : 'FAIL',
                                    style: TextStyle(
                                      color: entry.value
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Action Buttons
              ElevatedButton(
                onPressed: _isRunningTests ? null : _runComprehensiveTest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E88E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  _isRunningTests
                      ? 'Running Tests...'
                      : 'Run Comprehensive Test',
                  style: const TextStyle(fontSize: 16),
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton(
                onPressed: _isRunningTests ? null : _runQuickTest,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E88E5),
                  side: const BorderSide(color: Color(0xFF1E88E5)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Quick Notification Test',
                  style: TextStyle(fontSize: 16),
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton(
                onPressed: _isRunningTests ? null : _simulatePushNotification,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: const BorderSide(color: Colors.orange),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Simulate Push Notification',
                  style: TextStyle(fontSize: 16),
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton(
                onPressed: _isRunningTests ? null : _resetFirebaseMessaging,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Reset Firebase Messaging',
                  style: TextStyle(fontSize: 16),
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton(
                onPressed:
                    _isRunningTests ? null : _testLocalNotificationDirect,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.purple,
                  side: const BorderSide(color: Colors.purple),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Test Local Notification Direct',
                  style: TextStyle(fontSize: 16),
                ),
              ),

              const SizedBox(height: 12),

              // Test WhatsApp-Style Notification Button
              OutlinedButton(
                onPressed:
                    _isRunningTests ? null : _testWhatsAppStyleNotification,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                  side: const BorderSide(color: Colors.green),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Test WhatsApp-Style Notification',
                  style: TextStyle(fontSize: 16),
                ),
              ),

              const SizedBox(height: 24),

              // Info Card
              Card(
                color: isDark ? const Color(0xFF212121) : Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: isDark ? Colors.blue[300] : Colors.blue[700],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Test Information',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color:
                                  isDark ? Colors.blue[300] : Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This screen tests the notification system components including Firebase messaging, preferences, and local notifications.',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.blue[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTestName(String testName) {
    return testName
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  Future<void> _runComprehensiveTest() async {
    setState(() {
      _isRunningTests = true;
      _statusMessage = 'Running comprehensive notification tests...';
      _testResults.clear();
    });

    try {
      final results = await NotificationTestHelper.runComprehensiveTest();

      setState(() {
        _testResults = results;
        _isRunningTests = false;

        final allPassed = results.values.every((result) => result);
        _statusMessage = allPassed
            ? '🎉 All tests passed! Notification system is ready.'
            : '⚠️ Some tests failed. Check the results above.';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _testResults['overall_success'] == true
                  ? 'All notification tests passed!'
                  : 'Some tests failed. Check the results.',
            ),
            backgroundColor: _testResults['overall_success'] == true
                ? Colors.green
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isRunningTests = false;
        _statusMessage = 'Error running tests: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _runQuickTest() async {
    setState(() {
      _isRunningTests = true;
      _statusMessage = 'Running quick notification test...';
    });

    try {
      final success = await NotificationTestHelper.testLocalNotification();

      setState(() {
        _isRunningTests = false;
        _statusMessage = success
            ? '✅ Quick test passed! Check your notifications.'
            : '❌ Quick test failed.';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Test notification sent! Check your notification panel.'
                  : 'Failed to send test notification.',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isRunningTests = false;
        _statusMessage = 'Error in quick test: $e';
      });
    }
  }

  Future<void> _simulatePushNotification() async {
    setState(() {
      _isRunningTests = true;
      _statusMessage = 'Simulating push notification...';
    });

    try {
      await NotificationTestHelper.simulatePushNotification();

      setState(() {
        _isRunningTests = false;
        _statusMessage = '📱 Push notification simulated successfully!';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Push notification simulation completed!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isRunningTests = false;
        _statusMessage = 'Error simulating push notification: $e';
      });
    }
  }

  Future<void> _resetFirebaseMessaging() async {
    setState(() {
      _isRunningTests = true;
      _statusMessage = 'Resetting Firebase Messaging Service...';
    });

    try {
      // Reset the Firebase Messaging Service
      final firebaseService = FirebaseMessagingService();
      firebaseService.resetInitialization();

      // Reinitialize it
      await firebaseService.initialize();

      setState(() {
        _isRunningTests = false;
        _statusMessage =
            '🔄 Firebase Messaging Service reset and reinitialized!';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Firebase Messaging Service reset successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isRunningTests = false;
        _statusMessage = 'Error resetting Firebase Messaging: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reset error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testLocalNotificationDirect() async {
    setState(() {
      _isRunningTests = true;
      _statusMessage = 'Testing local notification directly...';
    });

    try {
      // Test the local notification system directly
      final firebaseService = FirebaseMessagingService();
      await firebaseService.testLocalNotification();

      setState(() {
        _isRunningTests = false;
        _statusMessage = '🔔 Direct local notification test completed!';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Direct notification test completed! Check your notification panel.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isRunningTests = false;
        _statusMessage = 'Error testing local notification: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Direct test error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testWhatsAppStyleNotification() async {
    setState(() {
      _isRunningTests = true;
      _statusMessage = 'Testing WhatsApp-style notification...';
    });

    try {
      // Test the WhatsApp-style notification system directly
      final firebaseService = FirebaseMessagingService();
      await firebaseService.testWhatsAppStyleNotification();

      setState(() {
        _isRunningTests = false;
        _statusMessage = '💬 WhatsApp-style notification test completed!';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'WhatsApp-style notification test completed! Check your notification panel for grouped messages.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isRunningTests = false;
        _statusMessage = 'Error testing WhatsApp-style notification: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('WhatsApp-style test error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
