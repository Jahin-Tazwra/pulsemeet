import 'package:flutter/material.dart';
import 'package:pulsemeet/screens/home/nearby_pulses_tab.dart';
import 'package:pulsemeet/screens/home/my_pulses_tab.dart';
import 'package:pulsemeet/screens/home/chat_tab.dart';
import 'package:pulsemeet/screens/home/profile_tab.dart';
import 'package:pulsemeet/screens/pulse/location_selection_screen.dart';

/// Main home screen with bottom navigation
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // List of tabs
  late final List<Widget> _tabs = [
    const NearbyPulsesTab(),
    const MyPulsesTab(),
    const ChatTab(),
    const ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      body: _tabs[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withAlpha(15),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          // Use theme settings
          type: BottomNavigationBarType.fixed,
          backgroundColor: theme.colorScheme.surface,
          selectedItemColor:
              theme.colorScheme.primary, // Primary color for selected items
          unselectedItemColor: isDarkMode
              ? Colors.white60 // White with 60% opacity for dark mode
              : const Color(0xFF9E9E9E), // Grey for light mode
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          selectedIconTheme: const IconThemeData(size: 28),
          unselectedIconTheme: const IconThemeData(size: 24),
          elevation:
              0, // No elevation since we're using a container with shadow
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.explore),
              label: 'Nearby',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people),
              label: 'My Pulses',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const LocationSelectionScreen(),
            ),
          );
        },
        backgroundColor:
            theme.colorScheme.primary, // Use primary color from theme
        foregroundColor:
            theme.colorScheme.onPrimary, // Use on-primary color from theme
        shape: const CircleBorder(),
        elevation: 4,
        child: const Icon(Icons.add, size: 32),
      ),
    );
  }
}
