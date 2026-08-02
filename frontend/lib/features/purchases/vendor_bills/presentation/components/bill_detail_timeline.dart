/// Vendor Bill Detail Timeline — Chronological activity log with status changes, payments.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import '../../models/vendor_bill.dart';
import '../../models/bill_status.dart';
import 'package:apexbooks/features/sales/payments/models/payment_enums.dart';

class BillDetailTimeline extends StatelessWidget {
  const BillDetailTimeline({super.key, required this.bill});

  final VendorBill bill;

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
    if (bill.createdAt != null && bill.createdAt!.isNotEmpty) {
      events.add(TimelineEvent(
        title: 'Bill Created',
        subtitle: bill.status == BillStatus.draft ? 'Saved as draft' : 'Bill recorded',
        timestamp: DateTime.parse(bill.createdAt!),
        icon: Icons.add_circle_outline,
        color: Colors.blue,
        type: TimelineEventType.created,
      ));
    }

    // Status changes (simulated based on current status)
    if (bill.status != BillStatus.draft) {
      events.add(TimelineEvent(
        title: 'Status Changed to ${bill.status.name.toUpperCase()}',
        subtitle: _getStatusChangeDescription(bill.status),
        timestamp: bill.createdAt != null ? DateTime.parse(bill.createdAt!) : DateTime.now(),
        icon: _getStatusIcon(bill.status),
        color: _getStatusColor(bill.status),
        type: TimelineEventType.statusChange,
      ));
    }

    // Payment events
    if (bill.payments.isNotEmpty) {
      for (final payment in bill.payments) {
        if (payment.paymentDate.isNotEmpty) {
          events.add(TimelineEvent(
            title: 'Payment Received',
            subtitle: '${_formatMethod(payment.paymentMode)} — ${payment.referenceNumber ?? 'No reference'}',
            timestamp: DateTime.parse(payment.paymentDate),
            icon: Icons.account_balance_wallet,
            color: Colors.green,
            type: TimelineEventType.payment,
            metadata: {'amount': payment.amount.toString()},
          ));
        }
      }
    }

    // Sort by timestamp descending (newest first)
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return events;
  }

  String _getStatusChangeDescription(BillStatus status) {
    switch (status) {
      case BillStatus.draft:
        return 'Bill saved as draft';
      case BillStatus.posted:
        return 'Bill posted';
      case BillStatus.unpaid:
        return 'Bill is unpaid';
      case BillStatus.partiallyPaid:
        return 'Partially paid';
      case BillStatus.paid:
        return 'Fully paid';
      case BillStatus.cancelled:
        return 'Bill cancelled';
    }
  }

  IconData _getStatusIcon(BillStatus status) {
    switch (status) {
      case BillStatus.draft:
        return Icons.edit_outlined;
      case BillStatus.posted:
      case BillStatus.unpaid:
        return Icons.hourglass_bottom_outlined;
      case BillStatus.partiallyPaid:
        return Icons.pending_outlined;
      case BillStatus.paid:
        return Icons.paid_outlined;
      case BillStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  Color _getStatusColor(BillStatus status) {
    switch (status) {
      case BillStatus.draft:
        return Colors.grey;
      case BillStatus.posted:
      case BillStatus.unpaid:
        return Colors.blue;
      case BillStatus.partiallyPaid:
        return Colors.orange;
      case BillStatus.paid:
        return Colors.green;
      case BillStatus.cancelled:
        return Colors.grey;
    }
  }

  String _formatMethod(PaymentMode method) {
    return method.name.toUpperCase();
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
  payment,
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