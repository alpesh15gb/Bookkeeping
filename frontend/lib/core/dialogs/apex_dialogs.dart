/// Dialog framework. Every dialog in the app is built through [ApexDialogs]
/// so that visuals, animations, and dismiss behaviour stay consistent.
/// Never call `showDialog` directly — always use this service.
library;

import 'package:flutter/material.dart';

import '../theme/responsive.dart';
import '../theme/app_colors.dart';

/// Central dialog builder — uses bottom sheets on mobile for better UX.
class ApexDialogs {
  ApexDialogs._();

  static bool _isMobile(BuildContext context) =>
      ResponsiveLayout.isMobile(context);

  /// Shows a confirmation dialog (Yes / No).
  /// On mobile uses a bottom sheet for larger touch targets.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Yes',
    String cancelText = 'No',
    Color? confirmColor,
  }) async {
    if (_isMobile(context)) {
      return _mobileConfirm(
        context,
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        confirmColor: confirmColor,
      );
    }
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelText),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Mobile-optimized confirmation using bottom sheet.
  static Future<bool> _mobileConfirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    required String cancelText,
    Color? confirmColor,
  }) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(message, style: Theme.of(ctx).textTheme.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: (confirmColor != null
                    ? FilledButton.styleFrom(backgroundColor: confirmColor)
                    : FilledButton.styleFrom())
                    .copyWith(padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(vertical: 16))),
                child: Text(confirmText, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(cancelText, style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
    return ok ?? false;
  }

  /// Delete confirmation (with destructive styling).
  static Future<bool> delete(
    BuildContext context, {
    required String itemName,
    String itemType = 'record',
  }) async {
    return confirm(
      context,
      title: 'Delete $itemType',
      message: 'Are you sure you want to delete "$itemName"?\n\nThis action cannot be undone.',
      confirmText: 'Delete',
      confirmColor: Theme.of(context).extension<ApexColors>()?.danger ?? Colors.red,
    );
  }

  /// Shows a simple success dialog.
  static Future<void> success(
    BuildContext context, {
    required String message,
    String title = 'Success',
  }) {
    final colors = apexColors(context);
    return _infoDialog(context, title: title, message: message, icon: Icons.check_circle_outline, color: colors.success);
  }

  /// Shows a simple error dialog.
  static Future<void> error(
    BuildContext context, {
    required String message,
    String title = 'Error',
  }) {
    final colors = apexColors(context);
    return _infoDialog(context, title: title, message: message, icon: Icons.error_outline, color: colors.danger);
  }

  /// Shows a full-screen progress dialog (dismissable only via [dismissProgress]).
  static OverlayEntry showProgress(
    BuildContext context, {
    String message = 'Please wait…',
  }) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (ctx) => Material(
        color: Colors.black45,
        child: Center(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    return entry;
  }

  /// Unsaved changes confirmation.
  static Future<bool> unsavedChanges(BuildContext context) => confirm(
    context,
    title: 'Unsaved Changes',
    message: 'You have unsaved changes. Do you want to discard them?',
    confirmText: 'Discard',
    cancelText: 'Keep editing',
  );

  // -----------------------------------------------------------------------
  static Future<void> _infoDialog(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) {
    if (_isMobile(context)) {
      return showModalBottomSheet<void>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 48),
                const SizedBox(height: 16),
                Text(title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(message, style: Theme.of(ctx).textTheme.bodyMedium, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon, color: color, size: 48),
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
