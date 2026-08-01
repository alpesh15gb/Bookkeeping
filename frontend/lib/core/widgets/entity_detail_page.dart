/// Reusable entity detail page — renders any record as configurable sections
/// with an optional action menu and audit timeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../actions/action_menu.dart';
import '../theme/app_colors.dart';
import '../theme/responsive.dart';
import '../timeline/audit_timeline.dart';

export '../actions/action_menu.dart' show ActionItem;
export '../timeline/audit_timeline.dart' show TimelineEntry;

/// A section rendered inside a Card on the detail page.
class DetailSection {
  const DetailSection({required this.title, required this.rows});
  final String title;
  final List<DetailRow> rows;
}

/// A single label/value row within a section.
class DetailRow {
  const DetailRow(this.label, this.value);
  final String label;
  final String? value;
}

/// A field that is rendered as a chip or badge.
class DetailChip {
  const DetailChip({required this.label, required this.color});
  final String label;
  final Color color;
}

/// A generic detail screen. Provide [sections], optional [header] and [chips],
/// plus [actions] and [timeline] entries.
class EntityDetailPage extends ConsumerWidget {
  const EntityDetailPage({
    super.key,
    required this.title,
    required this.sections,
    this.header,
    this.chips,
    this.actions = const [],
    this.timeline = const [],
    this.appBarActions,
  });

  /// Screen title (app bar).
  final String title;

  /// Optional header widget shown at the top (avatar, name, type, etc.).
  final Widget? header;

  /// Chips shown beside the header (status, type, etc.).
  final List<DetailChip>? chips;

  /// Sections of label/value rows.
  final List<DetailSection> sections;

  /// Actions for the action menu (three-dot menu in app bar).
  final List<ActionItem> actions;

  /// Timeline entries (created, updated, etc.).
  final List<TimelineEntry> timeline;

  /// Additional app bar actions (favourite, etc.).
  final List<Widget>? appBarActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (actions.isNotEmpty) ActionMenu(actions: actions),
          ...?appBarActions,
        ],
      ),
      body: ListView.builder(
        padding: EdgeInsets.all(ResponsiveLayout.isMobile(context) ? 12 : 16),
        itemCount: _computeItemCount(),
        itemBuilder: (context, index) {
          if (index == 0 && (header != null || chips != null)) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ?header,
                    if (chips != null && chips!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: chips!.map((c) => _buildChip(c)).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          final hasHeader = header != null || chips != null;
          final sectionIndex = hasHeader ? index - 1 : index;

          if (sectionIndex < sections.length) {
            final section = sections[sectionIndex];
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Divider(),
                      for (final row in section.rows) _buildRow(row, context),
                    ],
                  ),
                ),
              ),
            );
          }

          // Timeline entry (last item)
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(child: AuditTimeline(entries: timeline)),
          );
        },
      ),
    );
  }

  int _computeItemCount() {
    int count = sections.length;
    if (header != null || chips != null) count++;
    if (timeline.isNotEmpty) count++;
    return count;
  }

  Widget _buildChip(DetailChip c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: c.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(ApexRadius.lg),
    ),
    child: Text(
      c.label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: c.color,
      ),
    ),
  );

  Widget _buildRow(DetailRow r, BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final labelColors = apexColors(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isMobile ? 80 : 100,
            child: Text(
              r.label,
              style: TextStyle(color: labelColors.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              r.value ?? '\u2014',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
