/// Centralized notification service. Every screen routes user-facing messages
/// (success, error, info, warning) through here instead of calling
/// `ScaffoldMessenger.showSnackBar` directly. This keeps styling, dismissal
/// and analytics consistent app-wide.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';

/// Visual tone of a notification, mapping to semantic colors.
enum NotificationTone { success, error, info, warning }

/// A queued notification to display.
@immutable
class NotificationData {
  const NotificationData({
    required this.message,
    this.tone = NotificationTone.info,
    this.title,
    this.actionLabel,
    this.onAction,
    this.duration = const Duration(seconds: 4),
  });

  final String message;
  final NotificationTone tone;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
}

/// The single entry point for surfacing messages to the user.
///
/// Usage from any widget with a [BuildContext]:
///   ```dart
///   ref.read(notificationServiceProvider).success(context, 'Saved');
///   ref.read(notificationServiceProvider).error(context, apiError.message);
///   ```
class NotificationService {
  NotificationService();

  GlobalKey<ScaffoldMessengerState>? _messengerKey;

  /// Wire the [ScaffoldMessenger] key from [ApexApp] so notifications can be
  /// shown even when the current route has no Scaffold.
  void attachMessenger(GlobalKey<ScaffoldMessengerState> key) =>
      _messengerKey = key;

  void show(BuildContext context, NotificationData data) {
    final messenger =
        _messengerKey?.currentState ?? ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(_build(context, data));
  }

  SnackBar _build(BuildContext context, NotificationData data) {
    final colors = Theme.of(context).extension<ApexColors>()!;
    final (fg, bg) = _palette(colors, data.tone);
    return SnackBar(
      content: Row(
        children: [
          Icon(_icon(data.tone), color: fg, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.title != null)
                  Text(
                    data.title!,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                Text(data.message, style: TextStyle(color: fg, fontSize: 14)),
              ],
            ),
          ),
          if (data.actionLabel != null && data.onAction != null)
            TextButton(
              onPressed: () {
                data.onAction!.call();
                _messengerKey?.currentState?.hideCurrentSnackBar();
              },
              style: TextButton.styleFrom(foregroundColor: fg),
              child: Text(data.actionLabel!),
            ),
        ],
      ),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      duration: data.duration,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ApexRadius.md)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    );
  }

  (Color, Color) _palette(ApexColors c, NotificationTone t) => switch (t) {
    NotificationTone.success => (c.surface, c.success),
    NotificationTone.error => (c.surface, c.danger),
    NotificationTone.warning => (c.surface, c.warning),
    NotificationTone.info => (c.surface, c.textPrimary),
  };

  IconData _icon(NotificationTone t) => switch (t) {
    NotificationTone.success => Icons.check_circle_rounded,
    NotificationTone.error => Icons.error_outline_rounded,
    NotificationTone.warning => Icons.warning_amber_rounded,
    NotificationTone.info => Icons.info_outline_rounded,
  };

  // Convenience helpers ------------------------------------------------
  void success(BuildContext context, String message, {String? title}) => show(
    context,
    NotificationData(
      message: message,
      tone: NotificationTone.success,
      title: title,
    ),
  );

  void error(BuildContext context, String message, {String? title}) => show(
    context,
    NotificationData(
      message: message,
      tone: NotificationTone.error,
      title: title,
    ),
  );

  void info(BuildContext context, String message, {String? title}) => show(
    context,
    NotificationData(
      message: message,
      tone: NotificationTone.info,
      title: title,
    ),
  );

  void warning(BuildContext context, String message, {String? title}) => show(
    context,
    NotificationData(
      message: message,
      tone: NotificationTone.warning,
      title: title,
    ),
  );
}

/// Provider for [NotificationService].
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});
