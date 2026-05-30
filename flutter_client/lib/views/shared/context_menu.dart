import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';

class ContextMenuItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  const ContextMenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });
}

class AppContextMenu extends StatelessWidget {
  final Widget child;
  final List<ContextMenuItem> items;

  const AppContextMenu({
    super.key,
    required this.child,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition);
      },
      child: child,
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy,
        position.dx + 1, position.dy + 1,
      ),
      items: items.map((item) => PopupMenuItem(
        child: Row(
          children: [
            Icon(item.icon, size: 16, color: item.isDestructive ? AppColors.error : AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(item.label, style: TextStyle(
              color: item.isDestructive ? AppColors.error : AppColors.textPrimary,
            )),
          ],
        ),
        onTap: item.onTap,
      )).toList(),
    );
  }
}

/// Convenience wrapper for list items with context menu
class ContextMenuListTile extends StatelessWidget {
  final Widget child;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onView;
  final VoidCallback? onDuplicate;

  const ContextMenuListTile({
    super.key,
    required this.child,
    this.onEdit,
    this.onDelete,
    this.onView,
    this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final items = <ContextMenuItem>[];
    if (onView != null) items.add(ContextMenuItem(label: 'View', icon: Icons.visibility_outlined, onTap: onView!));
    if (onEdit != null) items.add(ContextMenuItem(label: 'Edit', icon: Icons.edit_outlined, onTap: onEdit!));
    if (onDuplicate != null) items.add(ContextMenuItem(label: 'Duplicate', icon: Icons.copy_outlined, onTap: onDuplicate!));
    if (onDelete != null) items.add(ContextMenuItem(label: 'Delete', icon: Icons.delete_outlined, onTap: onDelete!, isDestructive: true));

    return AppContextMenu(items: items, child: child);
  }
}
