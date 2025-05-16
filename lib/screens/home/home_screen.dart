import 'package:flutter/material.dart';
import 'package:pulsemeet/screens/home/nearby_pulses_tab.dart';
import 'package:pulsemeet/screens/home/my_pulses_tab.dart';
import 'package:pulsemeet/screens/home/profile_tab.dart';
import 'package:pulsemeet/screens/pulse/create_pulse_screen.dart';
import 'package:pulsemeet/services/pulse_notifier.dart';

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
    const ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
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
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CreatePulseScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
