/// Generic action menu. Instead of rewriting dropdown menus per module, use
/// [ActionMenu] which takes a list of [ActionItem] and renders either a popup
/// menu or a bottom sheet depending on platform.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A single action shown in the menu.
@immutable
class ActionItem {
  const ActionItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
  final bool enabled;
}

/// Renders a popup menu (desktop) or bottom sheet (mobile) with the given
/// [actions]. Typically used as the trailing widget in a ListTile or AppBar.
class ActionMenu extends StatelessWidget {
  const ActionMenu({
    super.key,
    required this.actions,
    this.icon = Icons.more_vert_rounded,
    this.tooltip = 'Actions',
    this.iconSize = 20,
  });

  final List<ActionItem> actions;
  final IconData icon;
  final String tooltip;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    if (isDesktop) {
      return PopupMenuButton<String>(
        tooltip: tooltip,
        icon: Icon(icon, size: iconSize),
        onSelected: (key) {
          final action = actions.firstWhere((a) => a.label == key);
          if (action.enabled) action.onTap();
        },
        itemBuilder: (_) => actions
            .map(
              (a) => PopupMenuItem<String>(
                value: a.label,
                enabled: a.enabled,
                child: Row(
                  children: [
                    Icon(
                      a.icon,
                      size: 18,
                      color: a.destructive ? Colors.red : null,
                    ),
                    const SizedBox(width: 12),
                    Text(a.label),
                  ],
                ),
              ),
            )
            .toList(),
      );
    }

    // Mobile — bottom sheet
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: iconSize),
      onPressed: () => _showBottomSheet(context),
    );
  }

  void _showBottomSheet(BuildContext context) {
    final colors = apexColors(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(ApexRadius.sm),
                ),
              ),
              const SizedBox(height: 8),
              ...actions.map(
                (a) => ListTile(
                  leading: Icon(
                    a.icon,
                    color: a.destructive ? Colors.red : null,
                  ),
                  title: Text(a.label),
                  enabled: a.enabled,
                  onTap: a.enabled
                      ? () {
                          Navigator.pop(context);
                          a.onTap();
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
