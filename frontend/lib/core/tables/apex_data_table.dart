/// The reusable [ApexDataTable] — server-side paginated, sortable, filterable,
/// searchable data table with sticky header, bulk selection, column visibility
/// and keyboard navigation. Every list screen composes this with a feature's
/// columns + a controller that supplies the [Paged] rows.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/base_model.dart';
import '../network/dio_extensions.dart';
import '../widgets/states.dart';
import 'table_body.dart';
import 'table_column.dart';
import 'table_controller.dart';
import 'table_pagination.dart';
import 'table_toolbar.dart';

/// The complete table surface: toolbar + sticky-header grid + pagination,
/// reacting to the four async states (loading/empty/error/data).
class ApexDataTable<T extends BaseModel> extends StatefulWidget {
  const ApexDataTable({
    super.key,
    required this.controller,
    required this.columns,
    required this.rows,
    required this.isLoading,
    required this.error,
    required this.onRetry,
    this.onRowTap,
    this.onExport,
    this.onRefresh,
    this.searchHint = 'Search...',
    this.filterChips = const [],
    this.rowKey = _defaultKey,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyTitle = 'No records found',
    this.emptySubtitle,
    this.emptyActionLabel,
    this.onEmptyAction,
  });

  final ApexTableController controller;
  final List<ApexColumn<T>> columns;
  final Paged<T>? rows;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;
  final void Function(T row)? onRowTap;
  final VoidCallback? onExport;
  final VoidCallback? onRefresh;
  final String searchHint;
  final List<Widget> filterChips;
  final String Function(T) rowKey;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptySubtitle;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  static String _defaultKey(BaseModel r) => r.id;

  @override
  State<ApexDataTable<T>> createState() => _ApexDataTableState<T>();
}

class _ApexDataTableState<T extends BaseModel> extends State<ApexDataTable<T>> {
  final _focusNode = FocusNode();
  int _focusedRow = -1;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final rows = widget.rows?.items ?? <T>[];
    if (rows.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _focusedRow = (_focusedRow + 1).clamp(0, rows.length - 1));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _focusedRow = (_focusedRow - 1).clamp(0, rows.length - 1));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.enter && _focusedRow >= 0) {
      widget.onRowTap?.call(rows[_focusedRow]);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      widget.controller.clearSelection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          ApexTableToolbar<T>(
            controller: widget.controller,
            columns: widget.columns,
            onExport: widget.onExport,
            onRefresh: widget.onRefresh,
            searchHint: widget.searchHint,
            filterChips: widget.filterChips,
          ),
          Expanded(child: _body()),
          if (widget.rows != null)
            ApexPaginationControls(
              controller: widget.controller,
              paged: widget.rows!,
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (widget.isLoading && widget.rows == null) {
      return const LoadingState(label: 'Loading...');
    }
    if (widget.error != null && widget.rows == null) {
      return ErrorView(message: widget.error!, onRetry: widget.onRetry);
    }
    final rows = widget.rows?.items ?? <T>[];
    if (rows.isEmpty) {
      return EmptyState(
        icon: widget.emptyIcon,
        title: widget.emptyTitle,
        subtitle: widget.emptySubtitle,
        actionLabel: widget.emptyActionLabel,
        onAction: widget.onEmptyAction,
      );
    }
    return SingleChildScrollView(
      child: ApexTableBody<T>(
        controller: widget.controller,
        columns: widget.columns,
        rows: rows,
        focusedRow: _focusedRow,
        onRowTap: widget.onRowTap,
        rowKey: widget.rowKey,
      ),
    );
  }
}
