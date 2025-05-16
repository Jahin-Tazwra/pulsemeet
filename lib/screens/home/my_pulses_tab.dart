import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'package:pulsemeet/widgets/pulse_card.dart';
import 'package:pulsemeet/screens/pulse/pulse_details_screen.dart';
import 'package:pulsemeet/services/supabase_service.dart';
import 'package:pulsemeet/services/pulse_notifier.dart';

/// Tab showing user's pulses
class MyPulsesTab extends StatefulWidget {
  const MyPulsesTab({super.key});

  @override
  State<MyPulsesTab> createState() => _MyPulsesTabState();
}

class _MyPulsesTabState extends State<MyPulsesTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Pulse> _createdPulses = [];
  List<Pulse> _joinedPulses = [];
  bool _isLoading = true;
  String? _errorMessage;
  late final StreamSubscription<Pulse> _pulseCreatedSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchMyPulses();

    // Listen for pulse creation events
    _pulseCreatedSubscription =
        PulseNotifier().onPulseCreated.listen((newPulse) {
      debugPrint('MyPulsesTab: Received pulse created event: ${newPulse.id}');
      // Refresh the list of pulses when a new pulse is created
      _fetchMyPulses();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pulseCreatedSubscription.cancel();
    super.dispose();
  }

  Future<void> _fetchMyPulses() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabaseService =
          Provider.of<SupabaseService>(context, listen: false);

      // Get current user ID
      final userId = supabaseService.currentUserId;
      if (userId == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'User not authenticated';
        });
        return;
      }

      // Get created and joined pulses using the SupabaseService methods
      final createdPulses = await supabaseService.getCreatedPulses();
      final joinedPulses = await supabaseService.getJoinedPulses();

      setState(() {
        _createdPulses = createdPulses;
        _joinedPulses = joinedPulses;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching pulses: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error fetching pulses: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Pulses'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Created'),
            Tab(text: 'Joined'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchMyPulses,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchMyPulses,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildPulsesList(_createdPulses, 'created'),
        _buildPulsesList(_joinedPulses, 'joined'),
      ],
    );
  }

  Widget _buildPulsesList(List<Pulse> pulses, String type) {
    if (pulses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == 'created' ? Icons.add_circle_outline : Icons.group_add,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'No $type pulses',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              type == 'created'
                  ? 'Create a new pulse to get started!'
                  : 'Join pulses to see them here!',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchMyPulses,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: pulses.length,
        itemBuilder: (context, index) {
          final pulse = pulses[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: PulseCard(
              pulse: pulse,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PulseDetailsScreen(pulse: pulse),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
