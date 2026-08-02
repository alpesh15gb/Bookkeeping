/// Invoice Detail Timeline — Chronological activity log with status changes, emails, prints.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import '../../models/invoice.dart';
import '../../models/invoice_status.dart';
import '../../payments/models/payment_enums.dart';

class InvoiceDetailTimeline extends StatelessWidget {
  const InvoiceDetailTimeline({super.key, required this.invoice});

  final Invoice invoice;

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
    if (invoice.createdAt != null) {
      events.add(TimelineEvent(
        title: 'Invoice Created',
        subtitle: invoice.status == InvoiceStatus.draft ? 'Saved as draft' : 'Invoice generated',
        timestamp: _parseDate(invoice.createdAt) ?? DateTime.now(),
        icon: Icons.add_circle_outline,
        color: Colors.blue,
        type: TimelineEventType.created,
      ));
    }

    // Status changes (simulated based on current status)
    if (invoice.status != InvoiceStatus.draft) {
      events.add(TimelineEvent(
        title: 'Status Changed to ${invoice.status.name.toUpperCase()}',
        subtitle: _getStatusChangeDescription(invoice.status),
        timestamp: _parseDate(invoice.updatedAt) ?? _parseDate(invoice.createdAt) ?? DateTime.now(),
        icon: _getStatusIcon(invoice.status),
        color: _getStatusColor(invoice.status),
        type: TimelineEventType.statusChange,
      ));
    }

    // Payment events
    final payments = invoice.payments;
    if (payments.isNotEmpty) {
      for (final payment in payments) {
        if (payment.paymentDate.isNotEmpty) {
          events.add(TimelineEvent(
            title: 'Payment Received',
            subtitle: '${_formatMethod(payment.paymentMode)} — ${payment.referenceNumber ?? 'No reference'}',
            timestamp: _parseDate(payment.paymentDate) ?? DateTime.now(),
            icon: Icons.account_balance_wallet,
            color: Colors.green,
            type: TimelineEventType.payment,
            metadata: {'amount': payment.amount.toString()},
          ));
        }
      }
    }

    // Sent event
    if (invoice.status == InvoiceStatus.sent || invoice.status == InvoiceStatus.partiallyPaid || invoice.status == InvoiceStatus.paid) {
      events.add(TimelineEvent(
        title: 'Invoice Sent',
        subtitle: 'Emailed to ${invoice.contactName ?? ''}',
        timestamp: _parseDate(invoice.updatedAt) ?? _parseDate(invoice.createdAt) ?? DateTime.now(),
        icon: Icons.send_outlined,
        color: Colors.indigo,
        type: TimelineEventType.sent,
      ));
    }

    // Print events (placeholder)
    // In real app, would come from audit log

    // Sort by timestamp descending (newest first)
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return events;
  }

  String _getStatusChangeDescription(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return 'Invoice saved as draft';
      case InvoiceStatus.sent:
        return 'Invoice sent to customer';
      case InvoiceStatus.partiallyPaid:
        return 'Partial payment received';
      case InvoiceStatus.paid:
        return 'Fully paid';
      case InvoiceStatus.overdue:
        return 'Payment overdue';
      case InvoiceStatus.cancelled:
        return 'Invoice cancelled';
      default:
        return '';
    }
  }

  IconData _getStatusIcon(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return Icons.edit_outlined;
      case InvoiceStatus.sent:
        return Icons.send_outlined;
      case InvoiceStatus.partiallyPaid:
        return Icons.hourglass_bottom_outlined;
      case InvoiceStatus.paid:
        return Icons.check_circle_outline;
      case InvoiceStatus.overdue:
        return Icons.warning_amber_outlined;
      case InvoiceStatus.cancelled:
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Color _getStatusColor(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return Colors.grey;
      case InvoiceStatus.sent:
        return Colors.blue;
      case InvoiceStatus.partiallyPaid:
        return Colors.orange;
      case InvoiceStatus.paid:
        return Colors.green;
      case InvoiceStatus.overdue:
        return Colors.red;
      case InvoiceStatus.cancelled:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _formatMethod(PaymentMode method) {
    return method.name.toUpperCase();
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
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