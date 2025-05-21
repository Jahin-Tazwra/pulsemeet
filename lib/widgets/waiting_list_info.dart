import 'package:flutter/material.dart';
import 'package:pulsemeet/models/waiting_list_entry.dart';
import 'package:pulsemeet/services/waiting_list_service.dart';
import 'package:pulsemeet/widgets/avatar.dart';

/// Widget to display waiting list information
class WaitingListInfo extends StatefulWidget {
  final String pulseId;
  
  const WaitingListInfo({
    super.key,
    required this.pulseId,
  });

  @override
  State<WaitingListInfo> createState() => _WaitingListInfoState();
}

class _WaitingListInfoState extends State<WaitingListInfo> {
  final _waitingListService = WaitingListService();
  
  @override
  void initState() {
    super.initState();
    _waitingListService.subscribeToWaitingList(widget.pulseId);
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // User's position
        StreamBuilder<int>(
          stream: _waitingListService.userPositionStream,
          builder: (context, snapshot) {
            final position = snapshot.data ?? 0;
            
            if (position <= 0) {
              return const SizedBox.shrink();
            }
            
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You are on the waiting list',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          position == 1
                              ? 'You are next in line! You will be automatically added when a spot opens up.'
                              : 'Your position: #$position. You will be automatically added when a spot opens up.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        
        // Waiting list
        StreamBuilder<List<WaitingListEntry>>(
          stream: _waitingListService.waitingListStream,
          builder: (context, snapshot) {
            final waitingList = snapshot.data ?? [];
            
            if (waitingList.isEmpty) {
              return const SizedBox.shrink();
            }
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Waiting List (${waitingList.length})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: waitingList.length,
                  itemBuilder: (context, index) {
                    final entry = waitingList[index];
                    return ListTile(
                      leading: UserAvatar(
                        userId: entry.userId,
                        avatarUrl: entry.avatarUrl,
                        size: 40,
                      ),
                      title: Text(
                        entry.displayName ?? entry.username ?? 'Unknown User',
                      ),
                      subtitle: Text(
                        'Position #${entry.position}',
                        style: theme.textTheme.bodySmall,
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
