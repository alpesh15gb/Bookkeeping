/// Sync status indicator — shows in the app shell's header/toolbar.
///
/// Displays the current [SyncSummary] as a compact chip with icon and label.
/// Tapping it opens the [SyncCenterSheet] for more detail.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_providers.dart';
import '../../../core/sync/sync_status.dart';

/// Small toolbar chip showing sync state.
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(syncSummaryProvider);

    return summaryAsync.when(
      data: (summary) => _SyncChip(summary: summary),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.summary});
  final SyncSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _chipColor(context, summary);
    final icon = _chipIcon(summary);

    return Tooltip(
      message: summary.statusLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showSyncCenter(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (summary.isActive)
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                summary.statusLabel,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _chipColor(BuildContext context, SyncSummary summary) {
    if (summary.hasIssues) return Colors.red.shade600;
    if (!summary.isOnline) return Colors.orange.shade700;
    if (summary.hasWork) return Colors.blue.shade600;
    return Colors.green.shade700;
  }

  IconData _chipIcon(SyncSummary summary) {
    if (summary.conflictCount > 0) return Icons.warning_amber_rounded;
    if (summary.failedCount > 0) return Icons.sync_problem_rounded;
    if (!summary.isOnline) return Icons.cloud_off_rounded;
    if (summary.pendingCount > 0) return Icons.cloud_upload_rounded;
    return Icons.cloud_done_rounded;
  }

  void _showSyncCenter(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const _SyncCenterSheet(),
    );
  }
}

/// Minimal sync centre bottom sheet (Phase 1 — informational only).
class _SyncCenterSheet extends ConsumerWidget {
  const _SyncCenterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(syncSummaryProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      maxChildSize: 0.8,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(24),
        children: [
          Text('Sync Centre', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          summaryAsync.when(
            data: (s) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Status', s.statusLabel),
                _row('Pending', '${s.pendingCount}'),
                _row('Failed', '${s.failedCount}'),
                _row('Conflicts', '${s.conflictCount}'),
                if (s.lastSyncedAt != null)
                  _row(
                    'Last synced',
                    s.lastSyncedAt!.toLocal().toString().substring(0, 19),
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    ref.read(syncSchedulerProvider).syncNow();
                  },
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Sync now'),
                ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        Text(value),
      ],
    ),
  );
}
