/// Audit timeline widget. Displays a vertical timeline of events (created,
/// updated, approved, cancelled, printed, emailed, etc.) for any record.
/// Reused across invoices, bills, orders, journals, etc.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A single timeline entry.
@immutable
class TimelineEntry {
  const TimelineEntry({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final String timestamp;
  final IconData icon;
  final Color color;
}

/// A vertical timeline widget.
class AuditTimeline extends StatelessWidget {
  const AuditTimeline({super.key, required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Activity',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No activity recorded yet.',
              style: TextStyle(color: colors.textMuted),
            ),
          )
        else
          ...List.generate(entries.length, (i) {
            final entry = entries[i];
            final isLast = i == entries.length - 1;
            return _TimelineRow(entry: entry, isLast: isLast, colors: colors);
          }),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.entry,
    required this.isLast,
    required this.colors,
  });

  final TimelineEntry entry;
  final bool isLast;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line + dot
          SizedBox(
            width: 40,
            child: Column(
              children: [
                const SizedBox(height: 6),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: entry.color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(child: Container(width: 2, color: colors.border)),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 8 : 16, right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(entry.icon, size: 14, color: entry.color),
                      const SizedBox(width: 6),
                      Text(
                        entry.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.subtitle,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  Text(
                    entry.timestamp,
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
