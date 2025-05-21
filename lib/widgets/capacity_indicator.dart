import 'package:flutter/material.dart';
import 'package:pulsemeet/models/pulse.dart';

/// Widget to display pulse capacity information
class CapacityIndicator extends StatelessWidget {
  final Pulse pulse;
  final bool showDetails;

  const CapacityIndicator({
    super.key,
    required this.pulse,
    this.showDetails = true,
  });

  @override
  Widget build(BuildContext context) {
    // If no max participants, don't show anything
    if (pulse.maxParticipants == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Calculate capacity percentage
    final percentage = pulse.capacityPercentage;

    // Determine color based on capacity
    Color progressColor;
    if (percentage < 50) {
      progressColor = const Color(0xFFBDBDBD); // Light grey
    } else if (percentage < 80) {
      progressColor = const Color(0xFF9E9E9E); // Medium grey
    } else {
      progressColor = const Color(0xFF757575); // Dark grey
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Capacity text
        Row(
          children: [
            Icon(
              pulse.isFull ? Icons.people_alt : Icons.people_outline,
              size: 16,
              color: theme.hintColor,
            ),
            const SizedBox(width: 4),
            Text(
              pulse.formattedParticipantCount,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
            if (pulse.isFull) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.error.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'FULL',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            if (pulse.hasWaitingList) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${pulse.waitingListCount} waiting',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),

        // Progress bar
        if (showDetails) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: theme.dividerColor,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 4,
            ),
          ),
        ],
      ],
    );
  }
}
