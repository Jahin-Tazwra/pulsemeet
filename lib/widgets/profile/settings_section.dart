import 'package:flutter/material.dart';

/// A widget that displays a section of settings
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final bool showDivider;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title
        Padding(
          padding: padding,
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        
        // Section content
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            children: children,
          ),
        ),
        
        // Optional divider
        if (showDivider)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Divider(),
          ),
      ],
    );
  }
}

/// A widget that displays a settings item with a title and optional subtitle
class SettingsItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showDivider;
  final Color? iconColor;
  final bool enabled;

  const SettingsItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.onTap,
    this.trailing,
    this.showDivider = true,
    this.iconColor,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? Theme.of(context).colorScheme.primary;
    
    return Column(
      children: [
        ListTile(
          leading: Icon(
            icon,
            color: enabled 
                ? effectiveIconColor 
                : Theme.of(context).disabledColor,
          ),
          title: Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: enabled 
                      ? Theme.of(context).colorScheme.onSurface 
                      : Theme.of(context).disabledColor,
                ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: enabled 
                            ? Theme.of(context).colorScheme.onSurfaceVariant 
                            : Theme.of(context).disabledColor,
                      ),
                )
              : null,
          trailing: trailing,
          onTap: enabled ? onTap : null,
          enabled: enabled,
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 72.0),
            child: Divider(height: 1),
          ),
      ],
    );
  }
}

/// A widget that displays a settings toggle item
class SettingsToggleItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool showDivider;
  final bool enabled;

  const SettingsToggleItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.value,
    this.onChanged,
    this.showDivider = true,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsItem(
      title: title,
      subtitle: subtitle,
      icon: icon,
      showDivider: showDivider,
      enabled: enabled,
      trailing: Switch(
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
      onTap: enabled
          ? () {
              if (onChanged != null) {
                onChanged!(!value);
              }
            }
          : null,
    );
  }
}

/// A widget that displays a settings radio item
class SettingsRadioItem<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final T value;
  final T groupValue;
  final ValueChanged<T?>? onChanged;
  final bool showDivider;
  final bool enabled;

  const SettingsRadioItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.value,
    required this.groupValue,
    this.onChanged,
    this.showDivider = true,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsItem(
      title: title,
      subtitle: subtitle,
      icon: icon,
      showDivider: showDivider,
      enabled: enabled,
      trailing: Radio<T>(
        value: value,
        groupValue: groupValue,
        onChanged: enabled ? onChanged : null,
      ),
      onTap: enabled
          ? () {
              if (onChanged != null) {
                onChanged!(value);
              }
            }
          : null,
    );
  }
}
