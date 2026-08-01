/// ApexBooks status badge component.
library;

import 'package:flutter/material.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

enum ApexBadgeTone { neutral, success, warning, danger, info, pending, syncing }

class ApexStatusBadge extends StatelessWidget {
  const ApexStatusBadge({
    super.key,
    required this.label,
    this.tone = ApexBadgeTone.neutral,
    this.icon,
    this.outlined = false,
  });

  final String label;
  final ApexBadgeTone tone;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (bg, fg) = _colors(colors);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm - 2,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: outlined ? Border.all(color: fg.withValues(alpha: 0.5)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(label, style: AppTypography.badge.copyWith(color: fg)),
        ],
      ),
    );
  }

  (Color, Color) _colors(ColorScheme c) => switch (tone) {
    ApexBadgeTone.success => (
      c.primaryContainer.withValues(alpha: 0.4),
      c.primary,
    ),
    ApexBadgeTone.warning => (
      Colors.amber.withValues(alpha: 0.15),
      Colors.amber.shade700,
    ),
    ApexBadgeTone.danger => (c.errorContainer.withValues(alpha: 0.4), c.error),
    ApexBadgeTone.info => (
      c.tertiaryContainer.withValues(alpha: 0.4),
      c.tertiary,
    ),
    ApexBadgeTone.pending => (
      Colors.grey.withValues(alpha: 0.15),
      Colors.grey.shade600,
    ),
    ApexBadgeTone.syncing => (
      Colors.blue.withValues(alpha: 0.1),
      Colors.blue.shade600,
    ),
    _ => (c.surfaceContainerHighest.withValues(alpha: 0.5), c.onSurfaceVariant),
  };
}

class ApexSyncBadge extends StatelessWidget {
  const ApexSyncBadge({
    super.key,
    required this.status,
    this.count,
    this.showLabel = true,
  });

  final String status;
  final int? count;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = switch (status) {
      'synced' => (ApexBadgeTone.success, Icons.cloud_done_rounded),
      'pending' => (ApexBadgeTone.pending, Icons.cloud_upload_rounded),
      'syncing' => (ApexBadgeTone.syncing, Icons.sync_rounded),
      'failed' => (ApexBadgeTone.danger, Icons.cloud_off_rounded),
      'conflict' => (ApexBadgeTone.danger, Icons.warning_amber_rounded),
      'localOnly' => (ApexBadgeTone.neutral, Icons.cloud_outlined),
      _ => (ApexBadgeTone.neutral, null),
    };
    final label = count != null
        ? '$count pending'
        : status[0].toUpperCase() + status.substring(1);
    return ApexStatusBadge(
      label: showLabel ? label : '',
      tone: tone,
      icon: icon,
      outlined: status == 'localOnly',
    );
  }
}
