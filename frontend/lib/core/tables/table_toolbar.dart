/// Toolbar above the [ApexDataTable]: debounced search, filter chips, column
/// visibility menu, export, and a refresh button. Reacts to and mutates an
/// [ApexTableController].
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/base_model.dart';
import '../theme/responsive.dart';
import 'table_column.dart';
import 'table_controller.dart';

/// The full-width toolbar shown above the table body.
class ApexTableToolbar<T extends BaseModel> extends StatefulWidget {
  const ApexTableToolbar({
    super.key,
    required this.controller,
    required this.columns,
    this.onExport,
    this.onRefresh,
    this.searchHint = 'Search...',
    this.filterChips = const [],
  });

  final ApexTableController controller;
  final List<ApexColumn<T>> columns;
  final VoidCallback? onExport;
  final VoidCallback? onRefresh;
  final String searchHint;

  /// Extra filter chips (status, date range, party) built by the feature.
  final List<Widget> filterChips;

  @override
  State<ApexTableToolbar<T>> createState() => _ApexTableToolbarState<T>();
}

class _ApexTableToolbarState<T extends BaseModel>
    extends State<ApexTableToolbar<T>> {
  late final TextEditingController _search;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.controller.value.search);
    widget.controller.addListener(_sync);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _sync() {
    if (_search.text != widget.controller.value.search) {
      _search.value = TextEditingValue(
        text: widget.controller.value.search,
        selection: TextSelection.collapsed(
          offset: widget.controller.value.search.length,
        ),
      );
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: AppConstants.searchDebounceMs),
      () => widget.controller.setSearch(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Search field
          SizedBox(
            width: ResponsiveLayout.isMobile(context) ? double.infinity : 260,
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: ResponsiveLayout.isMobile(context) ? 14 : 10),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          widget.controller.setSearch('');
                        },
                      )
                    : null,
              ),
            ),
          ),
          ...widget.filterChips,
          if (!ResponsiveLayout.isMobile(context)) const SizedBox(width: 8),
          // Column visibility
          _ColumnVisibilityMenu<T>(
            columns: widget.columns,
            controller: widget.controller,
          ),
          if (widget.onExport != null)
            IconButton(
              tooltip: 'Export',
              icon: const Icon(Icons.download_rounded, size: 20),
              onPressed: widget.onExport,
            ),
          if (widget.onRefresh != null)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: widget.onRefresh,
            ),
          if (widget.controller.value.hasActiveFilters)
            TextButton.icon(
              onPressed: widget.controller.clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Clear filters'),
            ),
        ],
      ),
    );
  }
}

class _ColumnVisibilityMenu<T extends BaseModel> extends StatelessWidget {
  const _ColumnVisibilityMenu({
    required this.columns,
    required this.controller,
  });
  final List<ApexColumn<T>> columns;
  final ApexTableController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Columns',
      icon: const Icon(Icons.view_column_rounded, size: 20),
      onSelected: controller.toggleColumnVisibility,
      itemBuilder: (_) => columns
          .map(
            (c) => PopupMenuItem<String>(
              value: c.id,
              child: Row(
                children: [
                  Icon(
                    controller.value.hiddenColumns.contains(c.id)
                        ? Icons.check_box_outline_blank
                        : Icons.check_box_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(c.label),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
