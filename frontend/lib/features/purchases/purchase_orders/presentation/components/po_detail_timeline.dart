/// Purchase Order Detail Timeline — Chronological activity log with status changes, receipts.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import '../../models/purchase_order.dart';
import '../../models/purchase_order_status.dart';

class PODetailTimeline extends StatelessWidget {
  const PODetailTimeline({super.key, required this.po});

  final PurchaseOrder po;

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
    if (po.createdAt != null && po.createdAt!.isNotEmpty) {
      events.add(TimelineEvent(
        title: 'Purchase Order Created',
        subtitle: po.status == PurchaseOrderStatus.draft ? 'Saved as draft' : 'Order placed',
        timestamp: DateTime.parse(po.createdAt!),
        icon: Icons.add_circle_outline,
        color: Colors.blue,
        type: TimelineEventType.created,
      ));
    }

    // Status changes
    if (po.status != PurchaseOrderStatus.draft) {
      events.add(TimelineEvent(
        title: 'Status Changed to ${po.status.name.toUpperCase()}',
        subtitle: _getStatusChangeDescription(po.status),
        timestamp: po.createdAt != null ? DateTime.parse(po.createdAt!) : DateTime.now(),
        icon: _getStatusIcon(po.status),
        color: _getStatusColor(po.status),
        type: TimelineEventType.statusChange,
      ));
    }

    // Receipt events
    if (po.receipts != null && po.receipts!.isNotEmpty) {
      for (final receipt in po.receipts!) {
        if (receipt.receiptDate != null && receipt.receiptDate!.isNotEmpty) {
          events.add(TimelineEvent(
            title: 'Goods Received',
            subtitle: '${receipt.grnNumber} — ${receipt.referenceNumber ?? 'No reference'}',
            timestamp: DateTime.parse(receipt.receiptDate!),
            icon: Icons.local_shipping,
            color: Colors.green,
            type: TimelineEventType.receipt,
            metadata: {'items': receipt.lineCount.toString()},
          ));
        }
      }
    }

    // Sort by timestamp descending (newest first)
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return events;
  }

  String _getStatusChangeDescription(PurchaseOrderStatus status) {
    switch (status) {
      case PurchaseOrderStatus.draft:
        return 'Order saved as draft';
      case PurchaseOrderStatus.pending:
        return 'Order pending approval';
      case PurchaseOrderStatus.approved:
        return 'Order approved';
      case PurchaseOrderStatus.partial:
        return 'Partially received';
      case PurchaseOrderStatus.completed:
        return 'Fully received and completed';
      case PurchaseOrderStatus.cancelled:
        return 'Order cancelled';
      default:
        return '';
    }
  }

  IconData _getStatusIcon(PurchaseOrderStatus status) {
    switch (status) {
      case PurchaseOrderStatus.draft:
        return Icons.edit_outlined;
      case PurchaseOrderStatus.pending:
        return Icons.hourglass_bottom_outlined;
      case PurchaseOrderStatus.approved:
        return Icons.check_circle_outline;
      case PurchaseOrderStatus.partial:
        return Icons.local_shipping_outlined;
      case PurchaseOrderStatus.completed:
        return Icons.done_all_outlined;
      case PurchaseOrderStatus.cancelled:
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Color _getStatusColor(PurchaseOrderStatus status) {
    switch (status) {
      case PurchaseOrderStatus.draft:
        return Colors.grey;
      case PurchaseOrderStatus.pending:
        return Colors.blue;
      case PurchaseOrderStatus.approved:
        return Colors.green;
      case PurchaseOrderStatus.partial:
        return Colors.orange;
      case PurchaseOrderStatus.completed:
        return Colors.green;
      case PurchaseOrderStatus.cancelled:
        return Colors.grey;
      default:
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
  receipt,
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