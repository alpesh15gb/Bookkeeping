/// Invoice Form Screen — Complete redesign following QuickBooks/Xero/Zoho patterns.
///
/// Features:
/// - Header section: Customer, dates, references
/// - Lines table: Spreadsheet-like with keyboard navigation
/// - Totals panel: GST-compliant breakdown
/// - Footer: Notes, terms, action buttons
/// - Keyboard shortcuts: Ctrl+S (save), Ctrl+Enter (add line), Escape (cancel)
/// - Responsive: Mobile stacked, Tablet, Desktop
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/features/auth/presentation/auth_controller.dart';
import 'invoice_form_notifier.dart';
import 'invoice_form_state.dart';
import 'components/invoice_header_section.dart';
import 'components/invoice_lines_table.dart';
import 'components/invoice_totals_panel.dart';
import 'components/invoice_footer.dart';

class InvoiceFormScreen extends ConsumerStatefulWidget {
  const InvoiceFormScreen({super.key, this.editId});

  /// Existing invoice to edit. The backend remains the source of truth for
  /// status, so we only edit drafts locally.
  final String? editId;

  @override
  ConsumerState<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends ConsumerState<InvoiceFormScreen> {
  late final FocusNode _formFocusNode;

  @override
  void initState() {
    super.initState();
    _formFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.editId != null) {
        ref.read(invoiceFormNotifierProvider.notifier).loadForEdit(widget.editId!);
      } else {
        ref.read(invoiceFormNotifierProvider.notifier).initializeNew();
      }
    });
  }

  @override
  void dispose() {
    _formFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(invoiceFormNotifierProvider);
    final notifier = ref.read(invoiceFormNotifierProvider.notifier);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final isMobile = ResponsiveLayout.isMobile(context);
    final isTablet = ResponsiveLayout.isTablet(context);

    return Focus(
      focusNode: _formFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleKeyEvent(event, notifier, state),
      child: Scaffold(
        backgroundColor: colors.surfaceMuted,
        body: SafeArea(
          child: Column(
            children: [
              // Page Header
              PageHeader(
                title: widget.editId != null ? 'Edit Invoice' : 'New Invoice',
                subtitle: widget.editId != null
                    ? 'Modify invoice details'
                    : 'Create a new sales invoice',
                actions: [
                  if (widget.editId != null)
                    ApexSecondaryButton(
                      label: 'Duplicate',
                      icon: Icons.content_copy,
                      onPressed: () => notifier.duplicate(),
                      tooltip: 'Duplicate this invoice (Ctrl+D)',
                    ),
                  ApexPrimaryButton(
                    label: state.isSaving ? 'Saving...' : 'Save',
                    icon: Icons.save,
                    onPressed: state.isSaving ? null : () => _save(notifier),
                    isLoading: state.isSaving,
                    tooltip: 'Save invoice (Ctrl+S)',
                  ),
                ],
              ),

              // Main Content
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 1200;
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.all(isMobile ? 16 : 24),
                      child: isWide && !isMobile
                          ? _buildWideLayout(context, state, notifier, fmt, colors)
                          : _buildNarrowLayout(context, state, notifier, fmt, colors),
                    );
                  },
                ),
              ),

              // Fixed Footer Actions (on mobile/tablet)
              if (isMobile || isTablet) _buildMobileFooter(state, notifier, colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWideLayout(
    BuildContext context,
    InvoiceFormState state,
    InvoiceFormNotifier notifier,
    NumberFormatter fmt,
    ApexColors colors,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Form (Header + Lines + Footer)
        Expanded(
          flex: 3,
          child: Column(
            children: [
              InvoiceHeaderSection(
                state: state,
                notifier: notifier,
                fmt: fmt,
              ),
              const SizedBox(height: 24),
              InvoiceLinesTable(
                state: state,
                notifier: notifier,
                fmt: fmt,
              ),
              const SizedBox(height: 24),
              InvoiceFooter(
                state: state,
                notifier: notifier,
                fmt: fmt,
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Right: Totals Panel (sticky)
        SizedBox(
          width: 380,
          child: InvoiceTotalsPanel(
            state: state,
            notifier: notifier,
            fmt: fmt,
            isSticky: true,
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(
    BuildContext context,
    InvoiceFormState state,
    InvoiceFormNotifier notifier,
    NumberFormatter fmt,
    ApexColors colors,
  ) {
    return Column(
      children: [
        InvoiceHeaderSection(
          state: state,
          notifier: notifier,
          fmt: fmt,
        ),
        const SizedBox(height: 24),
        InvoiceLinesTable(
          state: state,
          notifier: notifier,
          fmt: fmt,
        ),
        const SizedBox(height: 24),
        InvoiceTotalsPanel(
          state: state,
          notifier: notifier,
          fmt: fmt,
        ),
        const SizedBox(height: 24),
        InvoiceFooter(
          state: state,
          notifier: notifier,
          fmt: fmt,
        ),
      ],
    );
  }

  Widget _buildMobileFooter(
    InvoiceFormState state,
    InvoiceFormNotifier notifier,
    ApexColors colors,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: ApexSecondaryButton(
              label: 'Cancel',
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ApexPrimaryButton(
              label: state.isSaving ? 'Saving...' : 'Save',
              fullWidth: true,
              onPressed: state.isSaving ? null : () => _save(notifier),
              isLoading: state.isSaving,
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleKeyEvent(
    KeyEvent event,
    InvoiceFormNotifier notifier,
    InvoiceFormState state,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;

    // Ctrl+S: Save
    if (event.logicalKey == LogicalKeyboardKey.keyS &&
        (isControlPressed || isMetaPressed)) {
      _save(notifier);
      return KeyEventResult.handled;
    }

    // Ctrl+Enter: Add line (when in lines table)
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        (isControlPressed || isMetaPressed)) {
      notifier.addLine();
      return KeyEventResult.handled;
    }

    // Escape: Cancel edit / Close
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (state.editingLineIndex != null) {
        notifier.cancelLineEdit();
      } else {
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }

    // Ctrl+D: Duplicate
    if (event.logicalKey == LogicalKeyboardKey.keyD &&
        (isControlPressed || isMetaPressed) &&
        widget.editId != null) {
      notifier.duplicate();
      return KeyEventResult.handled;
    }

    // F2: Edit current line (handled by lines table)
    return KeyEventResult.ignored;
  }

  Future<void> _save(InvoiceFormNotifier notifier) async {
    final result = await notifier.save();
    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        ApexSnackBar.show(
          context: context,
          message: 'Invoice saved successfully',
          type: SnackBarType.success,
        );
        Navigator.of(context).pop(value);
      case Failure(:final error):
        ApexSnackBar.show(
          context: context,
          message: 'Failed to save: ${error.message}',
          type: SnackBarType.error,
        );
      default:
        break;
    }
  }
}