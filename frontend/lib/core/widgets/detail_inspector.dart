/// Reusable inline detail inspector — the fixed-width right-hand side panel a
/// master list shows in split view when a row is selected. Composes a header
/// (title + close), an optional subtitle, a scrollable body of label/value
/// rows and a trailing action bar. Autofocuses so **Esc** dismisses the panel,
/// mirroring the record-peek pattern in Zoho Books / ERPNext.
///
/// Reuses [DetailRow] from [entity_detail_page] so the label/value shape stays
/// consistent with the full-page detail view.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/responsive.dart';
import 'entity_detail_page.dart' show DetailRow;

export 'entity_detail_page.dart' show DetailRow;

/// An inline, fixed-width detail side panel for split-view list screens.
class DetailInspector extends StatelessWidget {
  const DetailInspector({
    super.key,
    required this.title,
    required this.rows,
    required this.onClose,
    this.subtitle,
    this.actions = const [],
    this.width = 360,
  });

  /// Panel title (usually the selected record's name).
  final String title;

  /// Optional secondary line under the title (e.g. "Type: Customer").
  final String? subtitle;

  /// Label/value rows rendered in the body.
  final List<DetailRow> rows;

  /// Called when the user presses the close button or Esc.
  final VoidCallback onClose;

  /// Trailing actions (edit, delete, …). Rendered stacked with spacing.
  final List<Widget> actions;

  /// Fixed panel width. Desktop-first; keep dense.
  final double width;

  /// On mobile, the inspector fills the available width (driven by the parent).
  /// On tablet/desktop, the fixed [width] is used.
  double responsiveWidth(BuildContext context) =>
      ResponsiveLayout.isMobile(context) ? double.infinity : width;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        width: responsiveWidth(context),
        color: colors.surfaceMuted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: colors.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Close (Esc)',
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (subtitle != null) ...[
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  for (final row in rows)
                    _InspectorRow(colors: colors, row: row),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    for (final action in actions) ...[
                      action,
                      const SizedBox(height: 12),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectorRow extends StatelessWidget {
  const _InspectorRow({required this.colors, required this.row});
  final ApexColors colors;
  final DetailRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              row.value ?? '—',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
