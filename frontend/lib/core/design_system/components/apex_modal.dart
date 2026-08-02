/// Modal and dialog components with consistent styling and animations.
library;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/responsive.dart';
import '../components/apex_button.dart';

/// A consistent modal bottom sheet for forms and complex actions.
class ApexModalBottomSheet extends StatelessWidget {
  const ApexModalBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.actions,
    this.isDismissible = true,
    this.enableDrag = true,
    this.maxHeightFactor = 0.9,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool isDismissible;
  final bool enableDrag;
  final double maxHeightFactor;

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    String? subtitle,
    List<Widget>? actions,
    bool isDismissible = true,
    bool enableDrag = true,
    double maxHeightFactor = 0.9,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ApexModalBottomSheet(
        title: title,
        subtitle: subtitle,
        actions: actions,
        maxHeightFactor: maxHeightFactor,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final textTheme = Theme.of(context).textTheme;
    final mediaQuery = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: mediaQuery.size.height * maxHeightFactor,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          if (title != null || subtitle != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 16 : 24,
                16,
                isMobile ? 16 : 24,
                8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title != null)
                          Text(
                            title!,
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (actions != null && actions!.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions!
                          .map((a) => Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: a,
                              ))
                          .toList(),
                    ),
                ],
              ),
            ),
          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 16 : 24,
                0,
                isMobile ? 16 : 24,
                isMobile ? 24 : 32,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// A confirmation dialog with consistent styling.
class ApexConfirmDialog extends StatelessWidget {
  const ApexConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.isDestructive = false,
    this.icon,
    this.onConfirm,
    this.onCancel,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;
  final IconData? icon;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
    IconData? icon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => ApexConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDestructive: isDestructive,
        icon: icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isDestructive ? colors.danger : colors.primary).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: isDestructive ? colors.danger : colors.primary, size: 24),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Text(message, style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary)),
      actions: [
        ApexTertiaryButton(
          label: cancelLabel,
          onPressed: () {
            Navigator.of(context).pop(false);
            onCancel?.call();
          },
        ),
        ApexPrimaryButton(
          label: confirmLabel,
          onPressed: () {
            Navigator.of(context).pop(true);
            onConfirm?.call();
          },
        ),
      ],
      actionsAlignment: MainAxisAlignment.end,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
    );
  }
}

/// A simple info dialog.
class ApexInfoDialog extends StatelessWidget {
  const ApexInfoDialog({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel = 'OK',
    this.onAction,
    this.icon,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
    String actionLabel = 'OK',
    VoidCallback? onAction,
    IconData? icon,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => ApexInfoDialog(
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        icon: icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: colors.primary, size: 24),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Text(message, style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary)),
      actions: [
        ApexPrimaryButton(
          label: actionLabel,
          onPressed: () {
            Navigator.of(context).pop();
            onAction?.call();
          },
        ),
      ],
      actionsAlignment: MainAxisAlignment.end,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
    );
  }
}

/// A loading dialog with progress.
class ApexLoadingDialog extends StatelessWidget {
  const ApexLoadingDialog({
    super.key,
    required this.message,
    this.progress, // 0.0 to 1.0, null for indeterminate
  });

  final String message;
  final double? progress;

  static void show({
    required BuildContext context,
    required String message,
    double? progress,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ApexLoadingDialog(message: message, progress: progress),
    );
  }

  static void hide(BuildContext context) {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              color: colors.primary,
            ),
            const SizedBox(height: 24),
            Text(message, style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary), textAlign: TextAlign.center),
            if (progress != null) ...[
              const SizedBox(height: 12),
              Text(
                '${(progress! * 100).toInt()}%',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A snackbar with consistent styling.
class ApexSnackBar {
  static void show({
    required BuildContext context,
    required String message,
    SnackBarType type = SnackBarType.info,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    Color backgroundColor;
    IconData icon;

    switch (type) {
      case SnackBarType.success:
        backgroundColor = colors.success;
        icon = Icons.check_circle_outline;
        break;
      case SnackBarType.error:
        backgroundColor = colors.danger;
        icon = Icons.error_outline;
        break;
      case SnackBarType.warning:
        backgroundColor = colors.warning;
        icon = Icons.warning_amber_outlined;
        break;
      case SnackBarType.info:
        backgroundColor = colors.info;
        icon = Icons.info_outline;
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
        duration: duration,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(icon, color: colors.onPrimary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: textTheme.bodyMedium?.copyWith(color: colors.onPrimary),
              ),
            ),
            if (actionLabel != null && onAction != null)
              TextButton(
                onPressed: () {
                  onAction();
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
                style: TextButton.styleFrom(
                  foregroundColor: colors.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: Text(actionLabel, style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}

enum SnackBarType { success, error, warning, info }