/// Purchase Return Detail Timeline — Chronological activity log with status changes.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import '../../models/purchase_return.dart';
import '../../models/purchase_return_status.dart';

class PRDetailTimeline extends StatelessWidget {
  const PRDetailTimeline({super.key, required this.pr});

  final PurchaseReturn pr;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    final events = _buildTimelineEvents();

    if (events.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 24 : 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timeline_outlined, size: 48, color: colors.textMuted),
              const SizedBox(height: 12),
              Text('No Activity Yet', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
              const SizedBox(height: 4),
              Text('Timeline events will appear here', style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final event = events[index];
        final isLast = index == events.length - 1;

        return _TimelineItem(
          event: event,
          isLast: isLast,
          colors: colors,
          textTheme: textTheme,
          isMobile: isMobile,
        );
      },
    );
  }

  List<TimelineEvent> _buildTimelineEvents() {
    final events = <TimelineEvent>[];

    // Created event
    if (pr.createdAt != null && pr.createdAt!.isNotEmpty) {
      events.add(TimelineEvent(
        title: 'Purchase Return Created',
        subtitle: pr.status == PurchaseReturnStatus.draft ? 'Saved as draft' : 'Return recorded',
        timestamp: DateTime.parse(pr.createdAt!),
        icon: Icons.add_circle_outline,
        color: Colors.blue,
        type: TimelineEventType.created,
      ));
    }

    // Status changes
    if (pr.status != PurchaseReturnStatus.draft) {
      events.add(TimelineEvent(
        title: 'Status Changed to ${pr.status.name.toUpperCase()}',
        subtitle: _getStatusChangeDescription(pr.status),
        timestamp: pr.createdAt != null ? DateTime.parse(pr.createdAt!) : DateTime.now(),
        icon: _getStatusIcon(pr.status),
        color: _getStatusColor(pr.status),
        type: TimelineEventType.statusChange,
      ));
    }

    // Sort by timestamp descending (newest first)
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return events;
  }

  String _getStatusChangeDescription(PurchaseReturnStatus status) {
    switch (status) {
      case PurchaseReturnStatus.draft:
        return 'Return saved as draft';
      case PurchaseReturnStatus.pending:
        return 'Return pending posting';
      case PurchaseReturnStatus.posted:
        return 'Return posted';
      case PurchaseReturnStatus.cancelled:
        return 'Return cancelled';
    }
  }

  IconData _getStatusIcon(PurchaseReturnStatus status) {
    switch (status) {
      case PurchaseReturnStatus.draft:
        return Icons.edit_outlined;
      case PurchaseReturnStatus.pending:
        return Icons.hourglass_bottom_outlined;
      case PurchaseReturnStatus.posted:
        return Icons.check_circle_outline;
      case PurchaseReturnStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  Color _getStatusColor(PurchaseReturnStatus status) {
    switch (status) {
      case PurchaseReturnStatus.draft:
        return Colors.grey;
      case PurchaseReturnStatus.pending:
        return Colors.blue;
      case PurchaseReturnStatus.posted:
        return Colors.green;
      case PurchaseReturnStatus.cancelled:
        return Colors.grey;
    }
  }
}

class TimelineEvent {
  const TimelineEvent({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.icon,
    required this.color,
    required this.type,
    this.metadata,
  });

  final String title;
  final String subtitle;
  final DateTime timestamp;
  final IconData icon;
  final Color color;
  final TimelineEventType type;
  final Map<String, String>? metadata;
}

enum TimelineEventType {
  created,
  statusChange,
  sent,
  printed,
  emailed,
  cancelled,
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.event,
    required this.isLast,
    required this.colors,
    required this.textTheme,
    required this.isMobile,
  });

  final TimelineEvent event;
  final bool isLast;
  final ApexColors colors;
  final TextTheme textTheme;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline connector
        Column(
          children: [
            // Dot
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: event.color,
                shape: BoxShape.circle,
                border: Border.all(color: colors.surface, width: 3),
              ),
            ),
            // Line
            if (!isLast)
              Expanded(
                child: Container(
                  width: 2,
                  color: colors.border,
                  margin: const EdgeInsets.only(left: 5),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),

        // Event content
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: event.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(event.icon, size: 18, color: event.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(event.title, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
                          Text(event.subtitle, style: textTheme.bodySmall?.copyWith(color: colors.textSecondary)),
                        ],
                      ),
                    ),
                    Text(
                      _formatTimestamp(event.timestamp),
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textMuted,
                        fontFamily: 'JetBrains Mono',
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                if (event.metadata != null && event.metadata!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: event.metadata!.entries.map((entry) => _metadataChip(label: entry.key, value: entry.value, colors: colors, textTheme: textTheme)).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _metadataChip({required String label, required String value, required ApexColors colors, required TextTheme textTheme}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        '$label: $value',
        style: textTheme.labelSmall?.copyWith(color: colors.textSecondary),
      ),
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays > 0) {
      return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}