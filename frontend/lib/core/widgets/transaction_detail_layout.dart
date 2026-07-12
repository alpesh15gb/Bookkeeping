import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/responsive.dart';
import 'page_header.dart';

/// Shared layout for transaction detail screens (invoices, bills, POs, etc.)
///
/// Wraps the common pattern: AppBar with title and action buttons, a scrollable
/// content area containing summary header, lines table, totals, optional notes,
/// and optional footer -- all centered and responsively padded.
///
/// Usage:
/// ```dart
/// TransactionDetailLayout(
///   title: 'INV-00123',
///   header: SummaryCard(...),
///   lines: LinesTable(...),
///   totals: TotalsCard(...),
///   actions: [PostButton(...), CancelButton(...)],
///   notes: NotesCard(...),
///   footer: AuditTimeline(...),
/// )
/// ```
class TransactionDetailLayout extends StatefulWidget {
  const TransactionDetailLayout({
    super.key,
    required this.title,
    required this.header,
    required this.lines,
    this.totals,
    this.actions = const [],
    this.notes,
    this.footer,
  });

  /// Transaction number / title displayed in the AppBar.
  final String title;

  /// Summary card showing key fields (vendor/customer, dates, status).
  final Widget header;

  /// Line items table or list.
  final Widget lines;

  /// Totals card (subtotal, tax, total, discount).
  final Widget? totals;

  /// Action buttons (Post, Cancel, Print, etc.) placed in the AppBar.
  final List<Widget> actions;

  /// Optional notes / terms section.
  final Widget? notes;

  /// Optional bottom content (audit trail, timeline, etc.).
  final Widget? footer;

  @override
  State<TransactionDetailLayout> createState() =>
      _TransactionDetailLayoutState();
}

class _TransactionDetailLayoutState extends State<TransactionDetailLayout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  EdgeInsets _responsivePadding(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return EdgeInsets.all(isMobile ? 12 : 24);
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      appBar: _TransactionAppBar(
        title: widget.title,
        actions: widget.actions,
        isMobile: isMobile,
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Scrollbar(
            child: ListView(
              padding: _responsivePadding(context),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header / summary card
                        ApexCard(child: widget.header),
                        const SizedBox(height: 16),

                        // Line items
                        ApexCard(padding: EdgeInsets.zero, child: widget.lines),
                        const SizedBox(height: 16),

                        // Totals
                        if (widget.totals != null) ...[
                          widget.totals!,
                          const SizedBox(height: 16),
                        ],

                        // Notes
                        if (widget.notes != null) ...[
                          ApexCard(child: widget.notes!),
                          const SizedBox(height: 16),
                        ],

                        // Footer (audit trail, etc.)
                        if (widget.footer != null) widget.footer!,

                        // Bottom spacing
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// AppBar for transaction detail screens with responsive layout.
///
/// On mobile the title stacks vertically above the action buttons.
/// On desktop they sit in a single row.
class _TransactionAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _TransactionAppBar({
    required this.title,
    required this.actions,
    required this.isMobile,
  });

  final String title;
  final List<Widget> actions;
  final bool isMobile;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 12);

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: isMobile
              ? _buildMobileLayout(context, theme, colors)
              : _buildDesktopLayout(context, theme, colors),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    ThemeData theme,
    ApexColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Back button + title row
        Row(
          children: [
            Tooltip(
              message: 'Go back',
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: colors.textPrimary,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actions,
          ),
        ],
      ],
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    ThemeData theme,
    ApexColors colors,
  ) {
    return Row(
      children: [
        Tooltip(
          message: 'Go back',
          child: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: colors.textPrimary,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: colors.textPrimary,
            ),
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: actions
                .map((w) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: w,
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}
