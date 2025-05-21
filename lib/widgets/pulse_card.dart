import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'package:pulsemeet/widgets/capacity_indicator.dart';

/// Card widget for displaying a pulse
class PulseCard extends StatelessWidget {
  final Pulse pulse;
  final VoidCallback? onTap;

  const PulseCard({
    super.key,
    required this.pulse,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Format date and time
    final dateFormat = DateFormat('E, MMM d');
    final timeFormat = DateFormat('h:mm a');
    final startDate = dateFormat.format(pulse.startTime);
    final startTime = timeFormat.format(pulse.startTime);
    final endTime = timeFormat.format(pulse.endTime);

    // Format distance
    String distanceText = '';
    if (pulse.distanceMeters != null) {
      if (pulse.distanceMeters! < 1000) {
        distanceText = '${pulse.distanceMeters!.toInt()} m away';
      } else {
        final km = pulse.distanceMeters! / 1000;
        distanceText = '${km.toStringAsFixed(1)} km away';
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row with emoji
              Row(
                children: [
                  if (pulse.activityEmoji != null) ...[
                    Text(
                      pulse.activityEmoji!,
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      pulse.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (pulse.distanceMeters != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        distanceText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Description
              Text(
                pulse.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              // Info row
              Row(
                children: [
                  // Date and time
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '$startDate, $startTime - $endTime',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Capacity indicator
                  CapacityIndicator(
                    pulse: pulse,
                    showDetails: false,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
