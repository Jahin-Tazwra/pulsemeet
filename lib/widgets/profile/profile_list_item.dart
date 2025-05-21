import 'package:flutter/material.dart';
import 'package:pulsemeet/models/profile.dart';
import 'package:pulsemeet/widgets/avatar.dart';
import 'package:timeago/timeago.dart' as timeago;

/// A list item for displaying a user profile
class ProfileListItem extends StatelessWidget {
  final Profile profile;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? subtitle;
  final bool showLastSeen;
  final bool showDivider;

  const ProfileListItem({
    super.key,
    required this.profile,
    this.onTap,
    this.trailing,
    this.subtitle,
    this.showLastSeen = true,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: UserAvatar(
            userId: profile.id,
            avatarUrl: profile.avatarUrl,
            size: 48.0,
          ),
          title: Text(
            profile.displayName ?? profile.username ?? 'User',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: subtitle ??
              (showLastSeen && profile.lastSeenAt != null
                  ? Text(
                      'Last seen ${timeago.format(profile.lastSeenAt!)}',
                      style: const TextStyle(
                        fontSize: 12.0,
                        color: Colors.grey,
                      ),
                    )
                  : null),
          trailing: trailing,
          onTap: onTap,
        ),
        if (showDivider)
          const Divider(
            height: 1.0,
            indent: 72.0,
          ),
      ],
    );
  }
}
