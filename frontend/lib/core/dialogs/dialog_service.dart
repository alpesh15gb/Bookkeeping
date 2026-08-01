/// Centralized dialog framework. Reusable confirm/delete/success/error/
/// progress/unsaved-changes dialogs so screens never hand-roll AlertDialogs.
/// Every dialog respects the ApexBooks theme and supports keyboard dismissal.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../widgets/states.dart';

/// The outcome of a confirm-style dialog.
enum DialogResult { confirm, cancel, discard }

/// Static helpers + a thin Riverpod wrapper for dialog invocation.
class DialogService {
  const DialogService();

  /// Generic confirmation dialog. Returns `true` when the user confirms.
  Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final colors = Theme.of(context).extension<ApexColors>()!;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          destructive
              ? Icons.warning_amber_rounded
              : Icons.help_outline_rounded,
          color: destructive ? colors.danger : colors.primary,
          size: 36,
        ),
        title: Text(
          title,
          style: GoogleFonts.instrumentSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(fontSize: 14, color: colors.textSecondary),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              cancelLabel,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: destructive ? colors.danger : colors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmLabel,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: colors.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Delete confirmation with the record name shown.
  Future<bool> confirmDelete(
    BuildContext context, {
    required String title,
    required String message,
  }) => confirm(
    context,
    title: title,
    message: message,
    confirmLabel: 'Delete',
    destructive: true,
  );

  /// Unsaved-changes guard. Offers Discard / Cancel (and optionally Save).
  Future<DialogResult> unsavedChanges(
    BuildContext context, {
    String title = 'Unsaved changes',
    String message = 'You have unsaved changes. Discard them and leave?',
    String saveLabel = 'Save',
    bool offerSave = false,
  }) async {
    final colors = Theme.of(context).extension<ApexColors>()!;
    final result = await showDialog<DialogResult>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.edit_note_rounded, size: 36, color: colors.warning),
        title: Text(
          title,
          style: GoogleFonts.instrumentSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(fontSize: 14, color: colors.textSecondary),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, DialogResult.cancel),
            child: Text(
              'Keep editing',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ),
          if (offerSave)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, DialogResult.confirm),
              child: Text(saveLabel),
            ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: colors.danger),
            onPressed: () => Navigator.pop(ctx, DialogResult.discard),
            child: Text(
              'Discard',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: colors.danger,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? DialogResult.cancel;
  }

  /// Informational success dialog (auto-dismissable action).
  Future<void> success(
    BuildContext context, {
    required String title,
    String? message,
    String okLabel = 'Done',
  }) async {
    final colors = Theme.of(context).extension<ApexColors>()!;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.check_circle_rounded, color: colors.success, size: 36),
        title: Text(
          title,
          style: GoogleFonts.instrumentSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        content: message == null
            ? null
            : Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(okLabel),
          ),
        ],
      ),
    );
  }

  /// Error dialog. Accepts an optional retry callback.
  Future<void> error(
    BuildContext context, {
    required String title,
    String? message,
    String okLabel = 'OK',
    String? retryLabel,
    VoidCallback? onRetry,
  }) async {
    final colors = Theme.of(context).extension<ApexColors>()!;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.error_outline_rounded, color: colors.danger, size: 36),
        title: Text(
          title,
          style: GoogleFonts.instrumentSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        content: message == null
            ? null
            : Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          if (retryLabel != null && onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                onRetry();
              },
              child: Text(retryLabel),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.danger),
            onPressed: () => Navigator.pop(ctx),
            child: Text(okLabel),
          ),
        ],
      ),
    );
  }

  /// Progress dialog with a spinner + optional message. Returns a function
  /// the caller invokes to close the dialog.
  Future<VoidCallback> progress(
    BuildContext context, {
    String? message,
    String title = 'Working...',
  }) async {
    final openedCompleter = Completer<void>();
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          if (!openedCompleter.isCompleted) openedCompleter.complete();
          return AlertDialog(
            content: Row(
              children: [
                const LoadingSpinner(size: 28),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (message != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          message,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Theme.of(
                              ctx,
                            ).extension<ApexColors>()?.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    await openedCompleter.future;
    return () => Navigator.of(context, rootNavigator: true).pop();
  }
}

/// Provider for [DialogService].
final dialogServiceProvider = Provider<DialogService>(
  (ref) => const DialogService(),
);
