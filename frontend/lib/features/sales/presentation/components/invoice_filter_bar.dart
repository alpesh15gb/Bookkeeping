/// Invoice Filter Bar — Advanced filtering with multi-select, date range, and bulk actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import '../../models/invoice_status.dart';

class InvoiceFilterBar extends ConsumerStatefulWidget {
  const InvoiceFilterBar({
    super.key,
    required this.onFilterChanged,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.onBulkAction,
  });

  final Function(InvoiceFilter) onFilterChanged;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onSelectionChanged;
  final void Function(String action) onBulkAction;

  @override
  ConsumerState<InvoiceFilterBar> createState() => _InvoiceFilterBarState();
}

class _InvoiceFilterBarState extends ConsumerState<InvoiceFilterBar> {
  bool _showAdvanced = false;
  DateTimeRange? _dateRange;
  String _searchQuery = '';
  InvoiceStatus? _statusFilter;
  String? _customerFilter;
  double? _minAmount;
  double? _maxAmount;

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, 16, isMobile ? 16 : 24, 0),
      child: Column(
        children: [
          // Main Search & Quick Filters
          Row(
            children: [
              // Search
              Expanded(
                flex: 3,
                child: ApexSearchField<String>(
                  label: 'Search',
                  hint: 'Search invoices... (/)',
                  prefixIcon: Icons.search,
                  value: _searchQuery,
                  onChanged: (v) {
                    _searchQuery = v;
                    _applyFilters();
                  },
                  suggestions: const [], // Could add recent searches
                  getLabel: (s) => s,
                ),
              ),
              const SizedBox(width: 12),

              // Status Filter
              SizedBox(
                width: 160,
                child: ApexDropdownField<InvoiceStatus?>(
                  label: 'Status',
                  value: _statusFilter,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Status')),
                    ...InvoiceStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(_formatStatus(s)))),
                  ],
                  onChanged: (v) {
                    _statusFilter = v;
                    _applyFilters();
                  },
                  hint: 'All',
                ),
              ),
              const SizedBox(width: 12),

              // Date Range
              SizedBox(
                width: 180,
                child: _DateRangePicker(
                  value: _dateRange,
                  onChanged: (range) {
                    _dateRange = range;
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 12),

              // Advanced Toggle
              ApexIconButton(
                icon: _showAdvanced ? Icons.expand_less : Icons.expand_more,
                onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                tooltip: _showAdvanced ? 'Hide advanced filters' : 'Show advanced filters',
              ),
            ],
          ),

          // Advanced Filters
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildAdvancedFilters(),
            crossFadeState: _showAdvanced ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeInOut,
          ),

          // Bulk Actions (when items selected)
          if (widget.selectedIds.isNotEmpty) _buildBulkActions(),
        ],
      ),
    );
  }

  Widget _buildAdvancedFilters() {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Advanced Filters', style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear all'),
                onPressed: _clearFilters,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Customer Filter
              Expanded(
                flex: 2,
                child: ApexTextField(
                  label: 'Customer',
                  controller: null,
                  initialValue: _customerFilter ?? '',
                  hint: 'Customer name or GSTIN',
                  onChanged: (v) {
                    _customerFilter = v.isEmpty ? null : v;
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Min Amount
              Expanded(
                child: ApexMonetaryField(
                  label: 'Min Amount',
                  controller: TextEditingController(text: _minAmount?.toStringAsFixed(2) ?? ''),
                  hint: '₹0.00',
                  onChanged: (v) {
                    _minAmount = double.tryParse(v.replaceAll(',', ''));
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Max Amount
              Expanded(
                child: ApexMonetaryField(
                  label: 'Max Amount',
                  controller: TextEditingController(text: _maxAmount?.toStringAsFixed(2) ?? ''),
                  hint: '₹0.00',
                  onChanged: (v) {
                    _maxAmount = double.tryParse(v.replaceAll(',', ''));
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBulkActions() {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final count = widget.selectedIds.length;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(
            '$count invoice${count == 1 ? '' : 's'} selected',
            style: textTheme.labelMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          ApexTertiaryButton(
            icon: Icons.print,
            label: 'Print',
            onPressed: () => widget.onBulkAction('print'),
          ),
          const SizedBox(width: 8),
          ApexTertiaryButton(
            icon: Icons.email,
            label: 'Email',
            onPressed: () => widget.onBulkAction('email'),
          ),
          const SizedBox(width: 8),
          ApexTertiaryButton(
            icon: Icons.cancel_outlined,
            label: 'Cancel',
            onPressed: () => widget.onBulkAction('cancel'),
            isDestructive: true,
          ),
          const SizedBox(width: 8),
          ApexTertiaryButton(
            icon: Icons.delete_outline,
            label: 'Delete',
            onPressed: () => widget.onBulkAction('delete'),
            isDestructive: true,
          ),
          const SizedBox(width: 8),
          ApexTertiaryButton(
            icon: Icons.clear,
            label: 'Clear',
            onPressed: () => widget.onSelectionChanged('', false), // Will clear all via parent
          ),
        ],
      ),
    );
  }

  void _applyFilters() {
    final filter = InvoiceFilter(
      searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      status: _statusFilter,
      dateFrom: _dateRange?.start,
      dateTo: _dateRange?.end,
      customerQuery: _customerFilter,
      minAmount: _minAmount,
      maxAmount: _maxAmount,
    );
    widget.onFilterChanged(filter);
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _statusFilter = null;
      _dateRange = null;
      _customerFilter = null;
      _minAmount = null;
      _maxAmount = null;
    });
    _applyFilters();
  }

  String _formatStatus(InvoiceStatus status) {
    return status.name[0].toUpperCase() + status.name.substring(1);
  }
}

class _DateRangePicker extends StatelessWidget {
  const _DateRangePicker({required this.value, required this.onChanged});

  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () async {
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDateRange: value,
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: colors.primary,
                brightness: Brightness.light,
              ),
            ),
            child: child!,
          ),
        );
        if (range != null) onChanged(range);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.date_range, size: 18, color: colors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value == null
                    ? 'Date Range'
                    : '${_formatDate(value!.start)} – ${_formatDate(value!.end)}',
                style: textTheme.bodyMedium?.copyWith(
                  color: value == null ? colors.textMuted : colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (value != null)
              IconButton(
                icon: Icon(Icons.clear, size: 16, color: colors.textMuted),
                onPressed: () => onChanged(null),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

/// Filter model
@immutable
class InvoiceFilter {
  const InvoiceFilter({
    this.searchQuery,
    this.status,
    this.dateFrom,
    this.dateTo,
    this.customerQuery,
    this.minAmount,
    this.maxAmount,
  });

  final String? searchQuery;
  final InvoiceStatus? status;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? customerQuery;
  final double? minAmount;
  final double? maxAmount;

  InvoiceFilter copyWith({
    String? searchQuery,
    InvoiceStatus? status,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? customerQuery,
    double? minAmount,
    double? maxAmount,
  }) {
    return InvoiceFilter(
      searchQuery: searchQuery ?? this.searchQuery,
      status: status ?? this.status,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      customerQuery: customerQuery ?? this.customerQuery,
      minAmount: minAmount ?? this.minAmount,
      maxAmount: maxAmount ?? this.maxAmount,
    );
  }
}