/// Reusable filter engine. Every list screen uses an [ApexFilterSet] to
/// compose date range, status, party, amount, GST, branch, warehouse and
/// other filters. The engine produces a [FilterSnapshot] that feeds into
/// [ApexTableController.statusFilter] / [activeFilters] and the API query.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A single filter that the engine knows how to build a widget for and how
/// to serialize into an API query parameter.
@immutable
class ApexFilter<T> {
  const ApexFilter({
    required this.id,
    required this.label,
    required this.items,
    required this.toQuery,
    this.icon,
    this.toLabel,
  });

  /// Unique identifier, e.g. `'status'`.
  final String id;

  /// Display label for the filter chip.
  final String label;

  /// All possible options.
  final List<T> items;

  /// Converts a selected value to a query parameter (value).
  /// Return `null` when no filter is active.
  final String? Function(T?)? toQuery;

  /// Optional icon for the chip.
  final IconData? icon;

  /// Converts an item to its display label. Defaults to .toString.
  final String Function(T)? toLabel;

  String displayLabel(T item) => toLabel?.call(item) ?? item.toString();
}

/// Snapshot of all active filter values, ready to be mapped to API params.
class FilterSnapshot {
  const FilterSnapshot({
    this.status,
    this.dateFrom,
    this.dateTo,
    this.party,
    this.minAmount,
    this.maxAmount,
    this.gstType,
    this.branch,
    this.warehouse,
    this.extra = const {},
  });

  final String? status;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? party;
  final double? minAmount;
  final double? maxAmount;
  final String? gstType;
  final String? branch;
  final String? warehouse;
  final Map<String, String?> extra;

  bool get hasAny =>
      status != null ||
      dateFrom != null ||
      dateTo != null ||
      party != null ||
      minAmount != null ||
      maxAmount != null ||
      gstType != null ||
      branch != null ||
      warehouse != null ||
      extra.values.any((v) => v != null);

  Map<String, dynamic> toQuery() {
    final q = <String, dynamic>{};
    if (status != null) q['status'] = status;
    if (dateFrom != null) q['date_from'] = dateFrom!.toIso8601String();
    if (dateTo != null) q['date_to'] = dateTo!.toIso8601String();
    if (party != null) q['party'] = party;
    if (minAmount != null) q['min_amount'] = minAmount;
    if (maxAmount != null) q['max_amount'] = maxAmount;
    if (gstType != null) q['gst_type'] = gstType;
    if (branch != null) q['branch'] = branch;
    if (warehouse != null) q['warehouse'] = warehouse;
    extra.forEach((k, v) {
      if (v != null) q[k] = v;
    });
    return q;
  }
}

/// Controller that manages the current filter selections.
class FilterController extends ChangeNotifier {
  FilterController({this.snapshot = const FilterSnapshot()});

  FilterSnapshot snapshot;

  void setStatus(String? s) {
    snapshot = FilterSnapshot(status: s, extra: snapshot.extra);
    notifyListeners();
  }

  void setDateRange(DateTime? from, DateTime? to) {
    snapshot = FilterSnapshot(
      dateFrom: from,
      dateTo: to,
      extra: snapshot.extra,
    );
    notifyListeners();
  }

  void setParty(String? p) {
    snapshot = FilterSnapshot(party: p, extra: snapshot.extra);
    notifyListeners();
  }

  void setAmountRange(double? min, double? max) {
    snapshot = FilterSnapshot(
      minAmount: min,
      maxAmount: max,
      extra: snapshot.extra,
    );
    notifyListeners();
  }

  void setGstType(String? t) {
    snapshot = FilterSnapshot(gstType: t, extra: snapshot.extra);
    notifyListeners();
  }

  void setExtra(String key, String? value) {
    snapshot = FilterSnapshot(extra: {...snapshot.extra, key: value});
    notifyListeners();
  }

  void clear() {
    snapshot = const FilterSnapshot();
    notifyListeners();
  }
}

/// Provider for a [FilterController] scoped to the current feature.
final filterControllerProvider =
    ChangeNotifierProvider.autoDispose<FilterController>((ref) {
      return FilterController();
    });

/// A filter chip bar widget. Pass an [ApexFilterSet] and it renders the chips.
class FilterChipBar extends StatelessWidget {
  const FilterChipBar({
    super.key,
    required this.controller,
    this.filters = const [],
    this.onChanged,
  });

  final FilterController controller;
  final List<ApexFilter<dynamic>> filters;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.snapshot;
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            // Active filter chips can be built from snapshot fields.
            if (s.status != null)
              Chip(
                label: Text('Status: ${s.status}'),
                onDeleted: () => controller.setStatus(null),
              ),
            if (s.party != null)
              Chip(
                label: Text('Party: ${s.party}'),
                onDeleted: () => controller.setParty(null),
              ),
            if (s.hasAny)
              ActionChip(
                label: const Text('Clear all'),
                onPressed: () => controller.clear(),
              ),
          ],
        );
      },
    );
  }
}
