/// Standard confirmation dialog with optional reason field.
///
/// Used for all destructive or irreversible actions.
/// Replaces ad-hoc [AlertDialog] and [showDialog] calls across the app.
library;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Result of a confirm dialog.
enum ConfirmResult { confirmed, cancelled }

/// Predefined dialog type presets.
enum ConfirmType {
  /// Generic confirmation (e.g. "Are you sure?")
  generic,

  /// Destructive action (e.g. delete, void, cancel)
  destructive,

  /// Warning about financial impact
  financial,
}

/// Shows a confirmation dialog with context-appropriate messaging.
///
/// On mobile uses a bottom sheet for better touch targets.
class ApexConfirmDialog {
  ApexConfirmDialog._();

  /// Shows a confirmation dialog.
  ///
  /// Returns `true` if confirmed, `false` if cancelled.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    ConfirmType type = ConfirmType.generic,
    bool requireReason = false,
    String? reasonHint,
    bool destructive = false,
  }) async {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return _showSheet(
        context,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        type: type,
        requireReason: requireReason,
        reasonHint: reasonHint,
        destructive: destructive,
      );
    }

    return _showDialog(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      type: type,
      requireReason: requireReason,
      reasonHint: reasonHint,
      destructive: destructive,
    );
  }

  static Future<bool> _showDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    required ConfirmType type,
    required bool requireReason,
    String? reasonHint,
    required bool destructive,
  }) async {
    final reasonCtrl = requireReason ? TextEditingController() : null;
    final colors = apexColors(context);

    final result = await showDialog<ConfirmResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            if (destructive)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.warning_rounded,
                  color: colors.danger,
                  size: 22,
                ),
              ),
            Expanded(child: Text(title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (requireReason && reasonCtrl != null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: reasonCtrl,
                decoration: InputDecoration(
                  labelText: reasonHint ?? 'Reason for this action *',
                  hintText: 'Explain why this change is necessary…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ApexRadius.md),
                  ),
                ),
                maxLines: 3,
                minLines: 2,
                autofocus: true,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ConfirmResult.cancelled),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () {
              if (requireReason && (reasonCtrl?.text.trim().isEmpty ?? false)) {
                return;
              }
              Navigator.pop(ctx, ConfirmResult.confirmed);
            },
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: colors.danger,
                    foregroundColor: colors.onPrimary,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    reasonCtrl?.dispose();
    return result == ConfirmResult.confirmed;
  }

  static Future<bool> _showSheet(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    required ConfirmType type,
    required bool requireReason,
    String? reasonHint,
    required bool destructive,
  }) async {
    final reasonCtrl = requireReason ? TextEditingController() : null;
    final colors = apexColors(context);

    final result = await showModalBottomSheet<ConfirmResult>(
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
              Row(
                children: [
                  if (destructive)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(
                        Icons.warning_rounded,
                        color: colors.danger,
                        size: 22,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () =>
                        Navigator.pop(ctx, ConfirmResult.cancelled),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(message, style: Theme.of(ctx).textTheme.bodyMedium),
              if (requireReason && reasonCtrl != null) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    labelText: reasonHint ?? 'Reason for this action *',
                    hintText: 'Explain why this change is necessary…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ApexRadius.md),
                    ),
                  ),
                  maxLines: 3,
                  minLines: 2,
                  autofocus: true,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(ctx, ConfirmResult.cancelled),
                      child: Text(cancelLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () {
                        if (requireReason &&
                            (reasonCtrl?.text.trim().isEmpty ?? false)) {
                          return;
                        }
                        Navigator.pop(ctx, ConfirmResult.confirmed);
                      },
                      style: destructive
                          ? FilledButton.styleFrom(
                              backgroundColor: colors.danger,
                              foregroundColor: colors.onPrimary,
                            )
                          : null,
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    reasonCtrl?.dispose();
    return result == ConfirmResult.confirmed;
  }
}
