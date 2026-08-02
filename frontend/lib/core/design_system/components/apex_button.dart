/// Consistent button components with proper states, loading, and keyboard support.
library;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/responsive.dart';
import '../index.dart';

/// Button size presets used across ApexBooks.
enum ButtonSize { small, medium, large }

/// Resolves horizontal/vertical padding for a button [ButtonSize].
({double horizontal, double vertical}) _buttonPadding(
  ButtonSize size,
  bool isMobile,
) {
  return switch (size) {
    ButtonSize.small => (horizontal: isMobile ? 12 : 14, vertical: isMobile ? 8 : 10),
    ButtonSize.medium => (horizontal: isMobile ? 16 : 20, vertical: isMobile ? 12 : 14),
    ButtonSize.large => (horizontal: isMobile ? 20 : 24, vertical: isMobile ? 16 : 18),
  };
}

double _buttonHeight(ButtonSize size) => switch (size) {
  ButtonSize.small => 40,
  ButtonSize.medium => 48,
  ButtonSize.large => 52,
};

/// Primary action button - filled, high emphasis.
class ApexPrimaryButton extends StatelessWidget {
  const ApexPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.fullWidth = false,
    this.tooltip,
    this.shortcut,
    this.size = ButtonSize.medium,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool fullWidth;
  final String? tooltip;
  final ShortcutActivator? shortcut;
  final ButtonSize size;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final enabled = onPressed != null && !isLoading;
    final padding = _buttonPadding(size, isMobile);

    final button = FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(colors.onPrimary),
              ),
            )
          : (icon != null ? Icon(icon, size: 18) : const SizedBox.shrink()),
      label: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        padding: EdgeInsets.symmetric(
          horizontal: padding.horizontal,
          vertical: padding.vertical,
        ),
        minimumSize: fullWidth ? const Size(double.infinity, 0) : Size(0, _buttonHeight(size)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: enabled ? 0 : 0,
        shadowColor: Colors.transparent,
      ),
    );

    final child = fullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

/// Secondary action button - outlined, medium emphasis.
class ApexSecondaryButton extends StatelessWidget {
  const ApexSecondaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.fullWidth = false,
    this.tooltip,
    this.isDestructive = false,
    this.size = ButtonSize.medium,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool fullWidth;
  final String? tooltip;
  final bool isDestructive;
  final ButtonSize size;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final enabled = onPressed != null && !isLoading;
    final padding = _buttonPadding(size, isMobile);

    final borderColor = isDestructive ? colors.danger : colors.border;
    final textColor = isDestructive ? colors.danger : colors.textPrimary;
    final bgColor = isDestructive ? colors.danger.withValues(alpha: 0.08) : colors.surface;

    final button = OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : (icon != null ? Icon(icon, size: 18) : const SizedBox.shrink()),
      label: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: enabled ? textColor : colors.textMuted,
            ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: enabled ? textColor : colors.textMuted,
        backgroundColor: enabled ? bgColor : colors.surfaceMuted,
        side: BorderSide(color: enabled ? borderColor : colors.border, width: 1.5),
        padding: EdgeInsets.symmetric(
          horizontal: padding.horizontal,
          vertical: padding.vertical,
        ),
        minimumSize: fullWidth ? const Size(double.infinity, 0) : Size(0, _buttonHeight(size)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    final child = fullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

/// Tertiary action button - text only, low emphasis.
class ApexTertiaryButton extends StatelessWidget {
  const ApexTertiaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.tooltip,
    this.isDestructive = false,
    this.size = ButtonSize.medium,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? tooltip;
  final bool isDestructive;
  final ButtonSize size;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final enabled = onPressed != null && !isLoading;
    final padding = _buttonPadding(size, isMobile);

    final textColor = isDestructive ? colors.danger : colors.primary;

    final button = TextButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : (icon != null ? Icon(icon, size: 18) : const SizedBox.shrink()),
      label: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: enabled ? textColor : colors.textMuted,
            ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: enabled ? textColor : colors.textMuted,
        padding: EdgeInsets.symmetric(
          horizontal: padding.horizontal,
          vertical: padding.vertical,
        ),
        minimumSize: Size(0, _buttonHeight(size)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Icon-only button for dense toolbars.
class ApexIconButton extends StatelessWidget {
  const ApexIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 40,
    this.isDestructive = false,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool isDestructive;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final enabled = onPressed != null;
    final isDestructive = this.isDestructive;

    final bgColor = selected
        ? (isDestructive ? colors.danger.withValues(alpha: 0.12) : colors.primary.withValues(alpha: 0.12))
        : (enabled ? colors.surfaceMuted : colors.surfaceMuted.withValues(alpha: 0.5));

    final iconColor = isDestructive
        ? (enabled ? colors.danger : colors.textMuted)
        : (selected ? colors.primary : (enabled ? colors.textPrimary : colors.textMuted));

    final button = InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: size * 0.55, color: iconColor),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Dropdown button for action menus.
class ApexDropdownButton extends StatelessWidget {
  const ApexDropdownButton({
    super.key,
    required this.items,
    this.onSelected,
    this.tooltip,
    this.icon = Icons.more_vert,
    this.alignment = AlignmentDirectional.centerEnd,
  });

  final List<ApexDropdownItem> items;
  final ValueChanged<String?>? onSelected;
  final String? tooltip;
  final IconData icon;
  final AlignmentDirectional alignment;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);

    final button = PopupMenuButton<String>(
      onSelected: onSelected,
      icon: Icon(icon, color: colors.textSecondary, size: 20),
      tooltip: tooltip,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      itemBuilder: (context) => items.map((item) {
        return PopupMenuItem<String>(
          value: item.value,
          child: Row(
            children: [
              if (item.leadingIcon != null) ...[
                Icon(item.leadingIcon, size: 18, color: colors.textSecondary),
                const SizedBox(width: 12),
              ],
              Text(item.label),
            ],
          ),
        );
      }).toList(),
    );

    return button;
  }
}

/// Item for ApexDropdownButton.
class ApexDropdownItem {
  const ApexDropdownItem({
    required this.value,
    required this.label,
    this.leadingIcon,
  });

  final String value;
  final String label;
  final IconData? leadingIcon;
}

/// Button group for related actions.
class ApexButtonGroup extends StatelessWidget {
  const ApexButtonGroup({
    super.key,
    required this.children,
    this.spacing = 8,
    this.alignment = WrapAlignment.start,
  });

  final List<Widget> children;
  final double spacing;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignment,
      spacing: spacing,
      runSpacing: 8,
      children: children,
    );
  }
}

/// Floating action button for primary create actions.
class ApexFloatingActionButton extends StatelessWidget {
  const ApexFloatingActionButton({
    super.key,
    required this.onPressed,
    this.icon = Icons.add,
    this.label,
    this.tooltip,
    this.extended = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String? label;
  final String? tooltip;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);

    final fab = extended
        ? FloatingActionButton.extended(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(
              label ?? '',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.onPrimary,
                  ),
            ),
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          )
        : FloatingActionButton(
            onPressed: onPressed,
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Icon(icon),
          );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: fab);
    }
    return fab;
  }
}