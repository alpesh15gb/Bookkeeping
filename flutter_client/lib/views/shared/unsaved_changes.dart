import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';

// ═══════════════════════════════════════════════════════════════════
// UNSAVED CHANGES GUARD
// ═══════════════════════════════════════════════════════════════════

/// Wraps a page to prevent accidental navigation when there are unsaved changes.
///
/// When [isDirty] is true and the user attempts to pop the route,
/// a confirmation dialog is shown. If the user confirms, navigation
/// proceeds; otherwise the pop is blocked.
class UnsavedChangesGuard extends StatefulWidget {
  final bool isDirty;
  final Widget child;
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;

  const UnsavedChangesGuard({
    super.key,
    required this.isDirty,
    required this.child,
    this.title = 'Unsaved Changes',
    this.message =
        'You have unsaved changes. Are you sure you want to leave?',
    this.confirmLabel = 'Leave',
    this.cancelLabel = 'Stay',
  });

  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.isDirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _showConfirmDialog(context);
      },
      child: widget.child,
    );
  }

  void _showConfirmDialog(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.dialog,
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                widget.title,
                style: AppTextStyles.h3,
              ),
            ),
          ],
        ),
        content: Text(widget.message, style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(widget.cancelLabel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: AppColors.textWhite,
            ),
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && mounted) {
        Navigator.of(context).pop();
      }
    });
  }
}
