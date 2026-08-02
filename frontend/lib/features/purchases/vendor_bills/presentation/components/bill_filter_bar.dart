/// Vendor Bill Filter Bar — Advanced filtering with status, date, vendor, amount.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import '../../models/bill_status.dart';

class BillFilterBar extends StatelessWidget {
  const BillFilterBar({
    super.key,
    required this.onFilterChanged,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.onBulkAction,
  });

  final void Function(BillFilter) onFilterChanged;
  final Set<String> selectedIds;
  final void Function(String, bool) onSelectionChanged;
  final void Function(String) onBulkAction;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);
    final hasSelection = selectedIds.isNotEmpty;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: isMobile
          ? _buildMobileLayout(context, colors, textTheme, hasSelection)
          : _buildDesktopLayout(context, colors, textTheme, hasSelection),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    ApexColors colors,
    TextTheme textTheme,
    bool hasSelection,
  ) {
    return Row(
      children: [
        // Search
        Expanded(
          flex: 2,
          child: _SearchField(
            hint: 'Search bills... (/)',
            onChanged: (value) {},
            colors: colors,
          ),
        ),

        const SizedBox(width: 8),

        if (_hasActiveFilters)
          IconButton(
            icon: Icon(Icons.clear_all, color: colors.textSecondary),
            onPressed: () => onFilterChanged(const BillFilter()),
            tooltip: 'Clear all filters',
          ),

        const SizedBox(width: 8),

        // Status Filter
        _buildStatusFilter(colors, textTheme),

        const SizedBox(width: 12),

        // Date Range Filter
        _buildDateRangeFilter(colors, textTheme),

        const SizedBox(width: 12),

        // Vendor Filter
        _buildVendorFilter(colors, textTheme),

        const SizedBox(width: 12),

        // Amount Range Filter
        _buildAmountFilter(colors, textTheme),

        const Spacer(),

        // Selection indicator + Bulk actions
        if (hasSelection) _buildSelectionBar(context, colors, textTheme),
      ],
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    ApexColors colors,
    TextTheme textTheme,
    bool hasSelection,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search
        _SearchField(
          hint: 'Search bills... (/)',
          onChanged: (value) {},
          colors: colors,
        ),

        const SizedBox(height: 12),

        // Filter chips row (scrollable)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildStatusFilter(colors, textTheme),
              const SizedBox(width: 8),
              _buildDateRangeFilter(colors, textTheme),
              const SizedBox(width: 8),
              _buildVendorFilter(colors, textTheme),
              const SizedBox(width: 8),
              _buildAmountFilter(colors, textTheme),
            ],
          ),
        ),

        if (hasSelection) ...[
          const SizedBox(height: 12),
          _buildSelectionBar(context, colors, textTheme),
        ],
      ],
    );
  }

  Widget _buildStatusFilter(ApexColors colors, TextTheme textTheme) {
    return _FilterChip(
      label: 'Status',
      value: _activeStatus?.name ?? 'All',
      onTap: () => _showStatusPicker(),
      trailing: _activeStatus != null ? Icons.filter_alt : Icons.filter_list,
    );
  }

  Widget _buildDateRangeFilter(ApexColors colors, TextTheme textTheme) {
    return _FilterChip(
      label: 'Date',
      value: _dateRangeLabel,
      onTap: () => _showDateRangePicker(),
      trailing: _dateRange != null ? Icons.filter_alt : Icons.filter_list,
    );
  }

  Widget _buildVendorFilter(ApexColors colors, TextTheme textTheme) {
    return _FilterChip(
      label: 'Vendor',
      value: _activeVendor?.name ?? 'All',
      onTap: () => _showVendorPicker(),
      trailing: _activeVendor != null ? Icons.filter_alt : Icons.filter_list,
    );
  }

  Widget _buildAmountFilter(ApexColors colors, TextTheme textTheme) {
    return _FilterChip(
      label: 'Amount',
      value: _amountRangeLabel,
      onTap: () => _showAmountRangePicker(),
      trailing: _amountRange != null ? Icons.filter_alt : Icons.filter_list,
    );
  }

  Widget _buildSelectionBar(
    BuildContext context,
    ApexColors colors,
    TextTheme textTheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${selectedIds.length} selected',
            style: textTheme.labelMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          _BulkActionButton(
            label: 'Print',
            icon: Icons.print,
            onPressed: () => onBulkAction('print'),
            colors: colors,
            textTheme: textTheme,
          ),
          _BulkActionButton(
            label: 'Email',
            icon: Icons.email,
            onPressed: () => onBulkAction('email'),
            colors: colors,
            textTheme: textTheme,
          ),
          _BulkActionButton(
            label: 'Cancel',
            icon: Icons.cancel,
            onPressed: () => onBulkAction('cancel'),
            colors: colors,
            textTheme: textTheme,
            isDestructive: true,
          ),
          _BulkActionButton(
            label: 'Delete',
            icon: Icons.delete,
            onPressed: () => onBulkAction('delete'),
            colors: colors,
            textTheme: textTheme,
            isDestructive: true,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.close, color: colors.primary, size: 20),
            onPressed: () {
              // Clear selection - would need to pass callback
            },
            tooltip: 'Clear selection',
          ),
        ],
      ),
    );
  }

  void _showStatusPicker() {
    // Show bottom sheet with status options
  }

  void _showDateRangePicker() {
    // Show date range picker
  }

  void _showVendorPicker() {
    // Show vendor picker
  }

  void _showAmountRangePicker() {
    // Show amount range dialog
  }

  // Active filter state (would be managed by parent or provider)
  final BillStatus? _activeStatus = null;
  final DateTimeRange? _dateRange = null;
  final Vendor? _activeVendor = null;
  final AmountRange? _amountRange = null;

  bool get _hasActiveFilters =>
      _activeStatus != null ||
      _dateRange != null ||
      _activeVendor != null ||
      _amountRange != null;

  String get _dateRangeLabel {
    final range = _dateRange;
    if (range == null) return 'All';
    return '${range.start.day}/${range.start.month} – ${range.end.day}/${range.end.month}';
  }

  String get _amountRangeLabel {
    final range = _amountRange;
    if (range == null) return 'All';
    return '₹${range.min} – ₹${range.max}';
  }
}

class _BulkActionButton extends StatelessWidget {
  const _BulkActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.colors,
    required this.textTheme,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final ApexColors colors;
  final TextTheme textTheme;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDestructive
        ? colors.errorContainer
        : colors.primaryContainer;
    final textColor = isDestructive
        ? colors.error
        : colors.primary;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Filter model
class BillFilter {
  const BillFilter({
    this.status,
    this.dateRange,
    this.vendorId,
    this.amountRange,
    this.searchQuery,
  });

  final BillStatus? status;
  final DateTimeRange? dateRange;
  final String? vendorId;
  final AmountRange? amountRange;
  final String? searchQuery;
}

class AmountRange {
  const AmountRange({required this.min, required this.max});

  final double min;
  final double max;
}

class Vendor {
  const Vendor({required this.id, required this.name});

  final String id;
  final String name;
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.hint,
    required this.onChanged,
    required this.colors,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(Icons.search, size: 18, color: colors.textMuted),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.onTap,
    required this.trailing,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final IconData trailing;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: textTheme.labelMedium?.copyWith(color: colors.textMuted)),
            const SizedBox(width: 6),
            Text(value, style: textTheme.labelMedium?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Icon(trailing, size: 16, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}