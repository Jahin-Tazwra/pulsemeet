import 'package:flutter/material.dart';

/// A widget that displays profile statistics
class ProfileStatsSection extends StatelessWidget {
  final int pulsesCreated;
  final int pulsesJoined;
  final int connections;
  final VoidCallback? onPulsesCreatedTap;
  final VoidCallback? onPulsesJoinedTap;
  final VoidCallback? onConnectionsTap;

  const ProfileStatsSection({
    super.key,
    required this.pulsesCreated,
    required this.pulsesJoined,
    required this.connections,
    this.onPulsesCreatedTap,
    this.onPulsesJoinedTap,
    this.onConnectionsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Pulses created
          Expanded(
            child: _buildStatItem(
              context,
              'Created',
              pulsesCreated.toString(),
              Icons.add_circle_outline,
              onPulsesCreatedTap,
            ),
          ),
          
          // Vertical divider
          Container(
            height: 40,
            width: 1,
            color: Theme.of(context).dividerColor,
          ),
          
          // Pulses joined
          Expanded(
            child: _buildStatItem(
              context,
              'Joined',
              pulsesJoined.toString(),
              Icons.group_outlined,
              onPulsesJoinedTap,
            ),
          ),
          
          // Vertical divider
          Container(
            height: 40,
            width: 1,
            color: Theme.of(context).dividerColor,
          ),
          
          // Connections
          Expanded(
            child: _buildStatItem(
              context,
              'Connections',
              connections.toString(),
              Icons.people_outline,
              onConnectionsTap,
            ),
          ),
        ],
      ),
    );
  }
  
  /// Build a stat item with label, value, and icon
  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    VoidCallback? onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          children: [
            // Icon
            Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            ),
            
            const SizedBox(height: 8),
            
            // Value
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            
            // Label
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
