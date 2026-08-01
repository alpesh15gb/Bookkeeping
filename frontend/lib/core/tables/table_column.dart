/// Column descriptors and state for [ApexDataTable]. A column declares how to
/// read a cell value from a row, whether it's sortable/filterable, its default
/// width/visibility, and an optional cell builder for custom rendering.
library;

import 'package:flutter/material.dart';

import '../api/base_model.dart';

/// How a column's cell is rendered.
typedef CellBuilder<T extends BaseModel> =
    Widget Function(BuildContext context, T row, int index);

/// Reads a raw cell value from a row.
typedef ValueReader<T extends BaseModel> = Object? Function(T row);

/// A column in an [ApexDataTable].
@immutable
class ApexColumn<T extends BaseModel> {
  const ApexColumn({
    required this.id,
    required this.label,
    required ValueReader<T> value,
    this.sortable = false,
    this.filterable = false,
    this.width = 160,
    this.minWidth = 80,
    this.maxWidth = 400,
    this.visible = true,
    this.alignment = Alignment.centerLeft,
    this.cellBuilder,
    this.headerBuilder,
    this.filterOptions,
  }) : _value = value;

  /// Stable id used for visibility/sort state persistence.
  final String id;

  /// Header label.
  final String label;

  /// Reads the raw cell value from a row (used for default text rendering
  /// and for sort comparisons).
  final ValueReader<T> _value;

  /// Public accessor for the cell value reader.
  Object? readValue(T row) => _value(row);

  /// Whether the column supports server-side sorting.
  final bool sortable;

  /// Whether the column supports a single-value filter (dropdown).
  final bool filterable;

  final double width;
  final double minWidth;
  final double maxWidth;
  final bool visible;
  final Alignment alignment;

  /// Optional custom cell widget. Defaults to a [Text] of [value].
  final CellBuilder<T>? cellBuilder;

  /// Optional custom header widget. Defaults to the label + sort arrow.
  final Widget Function(BuildContext, bool isSorted, SortDirection)?
  headerBuilder;

  /// Options for a filterable column (e.g. `['DRAFT','POSTED','PAID']`).
  final List<String>? filterOptions;
}

/// Sort state for the table (a single active sort column).
@immutable
class TableSort {
  const TableSort({this.columnId, this.direction = SortDirection.ascending});
  final String? columnId;
  final SortDirection direction;

  TableSort copyWith({String? columnId, SortDirection? direction}) => TableSort(
    columnId: columnId ?? this.columnId,
    direction: direction ?? this.direction,
  );

  /// The wire param name sent to the backend (the column id).
  String? get sortBy => columnId;
}
