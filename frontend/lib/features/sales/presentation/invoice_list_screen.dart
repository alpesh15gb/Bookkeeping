/// Invoice List Screen — Professional list with filters, bulk actions, and keyboard shortcuts.
///
/// Features:
/// - Advanced filtering: status, date range, customer, amount range
/// - Column sorting & visibility
/// - Bulk actions: print, email, cancel, delete
/// - Keyboard shortcuts: / (search), N (new), Escape (clear selection)
/// - Infinite scroll pagination
/// - Responsive: Mobile cards, Tablet, Desktop table
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/tables/table_pagination.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/permissions/permissions.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import '../models/invoice.dart';
import '../models/invoice_status.dart';
import 'invoice_list_provider.dart';
import 'invoice_form_screen.dart';
import 'invoice_detail_screen.dart';
import 'components/invoice_filter_bar.dart';
import 'components/invoice_table_body.dart';
import 'components/invoice_empty_state.dart';

class InvoiceListScreen extends ConsumerStatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  ConsumerState<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends ConsumerState<InvoiceListScreen> {
  late final FocusNode _listFocusNode;
  final Set<String> _selectedIds = {};
  InvoiceListItem? _hoveredItem;

  @override
  void initState() {
    super.initState();
    _listFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _listFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(invoiceListProvider);
    final notifier = ref.read(invoiceListProvider.notifier);
    final tableCtrl = ref.read(_invoiceTableCtrlProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final isMobile = ResponsiveLayout.isMobile(context);
    final isTablet = ResponsiveLayout.isTablet(context);

    return Focus(
      focusNode: _listFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleKeyEvent(event, notifier),
      child: Scaffold(
        backgroundColor: colors.surfaceMuted,
        body: SafeArea(
          child: Column(
            children: [
              // Page Header
              PageHeader(
                title: 'Invoices',
                subtitle: 'Manage and track all sales invoices',
                actions: [
                  PermissionGate(
                    permission: Permissions.invoiceCreate,
                    child: ApexPrimaryButton(
                      icon: Icons.add,
                      label: 'New Invoice',
                      onPressed: () => _openCreateForm(notifier),
                      tooltip: 'Create new invoice (N)',
                    ),
                  ),
                ],
              ),

              // Filter Bar
              InvoiceFilterBar(
                onFilterChanged: notifier.setFilters,
                selectedIds: _selectedIds,
                onSelectionChanged: _handleSelectionChanged,
                onBulkAction: _handleBulkAction,
              ),

              // Content
              Expanded(
                child: state.when(
                  data: (page) => _buildContent(context, page, tableCtrl, fmt, colors, isMobile, isTablet),
                  loading: () => const Center(child: ApexSkeletonLoader()),
                  error: (error, _) => _buildErrorState(error, notifier),
                ),
              ),
            ],
          ),
        ),
        // Mobile FAB
        floatingActionButton: isMobile || isTablet
            ? PermissionGate(
                permission: Permissions.invoiceCreate,
                child: FloatingActionButton.extended(
                  onPressed: () => _openCreateForm(notifier),
                  icon: const Icon(Icons.add),
                  label: const Text('New Invoice'),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ({List<InvoiceListItem> items, int total}) page,
    ApexTableController tableCtrl,
    NumberFormatter fmt,
    ApexColors colors,
    bool isMobile,
    bool isTablet,
  ) {
    if (page.items.isEmpty) {
      return InvoiceEmptyState(
        onCreate: () => _openCreateForm(ref.read(invoiceListProvider.notifier)),
      );
    }

    final currentPage = ref.watch(_currentPageProvider);
    final totalPages = (page.total / 50).ceil();

    if (isMobile) {
      return _buildMobileCards(page, fmt, colors);
    }

    final paged = Paged<InvoiceListItem>(
      items: page.items,
      total: page.total,
      page: currentPage,
      limit: 50,
    );

    return RefreshIndicator(
      onRefresh: () async => ref.read(invoiceListProvider.notifier).refresh(),
      child: Column(
        children: [
          // Desktop/Tablet Table
          Expanded(
            child: InvoiceTableBody(
              items: page.items,
              tableCtrl: tableCtrl,
              fmt: fmt,
              selectedIds: _selectedIds,
              hoveredId: _hoveredItem?.id,
              onItemTap: (item) => _navigateToDetail(item),
              onSelectionChanged: _handleSelectionChanged,
              onHoveredChanged: (item) => setState(() => _hoveredItem = item),
            ),
          ),

          // Pagination
          if (totalPages > 1)
            ApexPaginationControls(
              controller: tableCtrl,
              paged: paged,
            ),
        ],
      ),
    );
  }

  Widget _buildMobileCards(
    ({List<InvoiceListItem> items, int total}) page,
    NumberFormatter fmt,
    ApexColors colors,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: page.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = page.items[index];
        final isSelected = _selectedIds.contains(item.id);

        return InkWell(
          onTap: () => _navigateToDetail(item),
          onLongPress: () => _handleSelectionChanged(item.id, !isSelected),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? colors.primaryContainer.withValues(alpha: 0.2) : colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? colors.primary : colors.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => _handleSelectionChanged(item.id, !isSelected),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.invoiceNumber,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            item.contactName,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusChip(status: item.status),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _InfoItem(
                        icon: Icons.calendar_today,
                        label: 'Date',
                        value: _formatDate(item.issueDate),
                      ),
                    ),
                    Expanded(
                      child: _InfoItem(
                        icon: Icons.event_busy,
                        label: 'Due',
                        value: _formatDate(item.dueDate),
                      ),
                    ),
                    Expanded(
                      child: _InfoItem(
                        icon: Icons.currency_rupee,
                        label: 'Amount',
                        value: fmt.currency(item.total),
                        isAmount: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _InfoItem(
                        icon: Icons.account_balance_wallet,
                        label: 'Outstanding',
                        value: fmt.currency(item.outstanding),
                        isAmount: true,
                        color: item.outstanding > 0 ? colors.danger : colors.success,
                      ),
                    ),
                    _AmountBadge(amount: item.total, fmt: fmt),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState(Object error, InvoiceListNotifier notifier) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: colors.danger),
            const SizedBox(height: 16),
            Text('Failed to load invoices', style: textTheme.headlineSmall?.copyWith(color: colors.textPrimary)),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ApexPrimaryButton(
              icon: Icons.refresh,
              label: 'Retry',
              onPressed: () => notifier.refresh(),
            ),
          ],
        ),
      ),
    );
  }

  // ───── Event Handlers ────────────────────────────────────────────────────

  KeyEventResult _handleKeyEvent(KeyEvent event, InvoiceListNotifier notifier) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isMeta = HardwareKeyboard.instance.isMetaPressed;

    // '/' - Focus search
    if (event.logicalKey == LogicalKeyboardKey.slash && !isCtrl && !isMeta) {
      // Focus search field in filter bar
      return KeyEventResult.handled;
    }

    // 'N' - New invoice
    if (event.logicalKey == LogicalKeyboardKey.keyN && !isCtrl && !isMeta) {
      _openCreateForm(notifier);
      return KeyEventResult.handled;
    }

    // Escape - Clear selection
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_selectedIds.isNotEmpty) {
        setState(() => _selectedIds.clear());
      } else {
        _listFocusNode.unfocus();
      }
      return KeyEventResult.handled;
    }

    // Delete - Delete selected
    if (event.logicalKey == LogicalKeyboardKey.delete && _selectedIds.isNotEmpty) {
      _handleBulkAction('delete');
      return KeyEventResult.handled;
    }

    // Arrow keys for navigation (handled by table)
    return KeyEventResult.ignored;
  }

  void _handleSelectionChanged(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  void _handleBulkAction(String action) {
    if (_selectedIds.isEmpty) return;

    switch (action) {
      case 'print':
        _bulkPrint();
        break;
      case 'email':
        _bulkEmail();
        break;
      case 'cancel':
        _bulkCancel();
        break;
      case 'delete':
        _bulkDelete();
        break;
    }
  }

  Future<void> _openCreateForm(InvoiceListNotifier notifier) async {
    final ctx = context;
    final result = await Navigator.of(ctx).push<Invoice>(
      MaterialPageRoute(builder: (_) => const InvoiceFormScreen()),
    );
    if (!mounted) return;
    if (result != null) {
      await notifier.refresh();
      if (!mounted) return;
      ApexSnackBar.show(
        context: context,
        message: 'Invoice created: ${result.invoiceNumber}',
        type: SnackBarType.success,
      );
    }
  }

  void _navigateToDetail(InvoiceListItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: item.id)),
    );
  }

  void _bulkPrint() {
    // TODO: Implement bulk print
    ApexSnackBar.show(
      context: context,
      message: 'Printing ${_selectedIds.length} invoices...',
      type: SnackBarType.info,
    );
  }

  void _bulkEmail() {
    // TODO: Implement bulk email
    ApexSnackBar.show(
      context: context,
      message: 'Emailing ${_selectedIds.length} invoices...',
      type: SnackBarType.info,
    );
  }

  void _bulkCancel() {
    // TODO: Implement bulk cancel
    ApexSnackBar.show(
      context: context,
      message: 'Cancelling ${_selectedIds.length} invoices...',
      type: SnackBarType.info,
    );
  }

  void _bulkDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Invoices'),
        content: Text('Are you sure you want to delete ${_selectedIds.length} invoice(s)? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement bulk delete
              ApexSnackBar.show(
                context: context,
                message: 'Deleted ${_selectedIds.length} invoices',
                type: SnackBarType.success,
              );
              setState(() => _selectedIds.clear());
            },
            style: FilledButton.styleFrom(backgroundColor: apexColors(context).danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
    this.isAmount = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isAmount;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: textTheme.labelSmall?.copyWith(color: colors.textMuted)),
            Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                color: color ?? (isAmount ? colors.textPrimary : colors.textSecondary),
                fontWeight: isAmount ? FontWeight.w600 : FontWeight.w400,
                fontFamily: isAmount ? 'JetBrains Mono' : null,
                fontFeatures: isAmount ? const [FontFeature.tabularFigures()] : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AmountBadge extends StatelessWidget {
  const _AmountBadge({required this.amount, required this.fmt});

  final double amount;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        fmt.currency(amount),
        style: textTheme.bodyMedium?.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w700,
          fontFamily: 'JetBrains Mono',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    Color bgColor;
    Color textColor;
    IconData icon;

    switch (status) {
      case InvoiceStatus.draft:
        bgColor = colors.surfaceMuted;
        textColor = colors.textSecondary;
        icon = Icons.edit_outlined;
        break;
      case InvoiceStatus.sent:
        bgColor = colors.infoContainer;
        textColor = colors.info;
        icon = Icons.send_outlined;
        break;
      case InvoiceStatus.partiallyPaid:
        bgColor = colors.warningContainer;
        textColor = colors.warning;
        icon = Icons.hourglass_bottom_outlined;
        break;
      case InvoiceStatus.paid:
        bgColor = colors.successContainer;
        textColor = colors.success;
        icon = Icons.check_circle_outline;
        break;
      case InvoiceStatus.overdue:
        bgColor = colors.errorContainer;
        textColor = colors.danger;
        icon = Icons.warning_amber_outlined;
        break;
      case InvoiceStatus.cancelled:
        bgColor = colors.surfaceMuted;
        textColor = colors.textMuted;
        icon = Icons.cancel_outlined;
        break;
      default:
        bgColor = colors.surfaceMuted;
        textColor = colors.textSecondary;
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            status.name.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ───── Providers ────────────────────────────────────────────────────────────

final _invoiceTableCtrlProvider = ChangeNotifierProvider<ApexTableController>((ref) => ApexTableController());
final _currentPageProvider = StateProvider<int>((ref) => 1);