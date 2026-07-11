/// Reusable filter chips (status + key/value) that read/write an
/// [ApexTableController]. Composed into the table toolbar's `filterChips`.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../tables/table_controller.dart';
import 'filter_chip.dart';

/// A single-value dropdown filter chip (e.g. status).
class ApexStatusFilter extends StatelessWidget {
  const ApexStatusFilter({
    super.key,
    required this.controller,
    required this.options,
    this.label = 'Status',
  });

  final ApexTableController controller;
  final List<String> options;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final current = controller.value.statusFilter;
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: controller.setStatusFilter,
      itemBuilder: (_) => [
        const PopupMenuItem<String>(value: '', child: Text('All')),
        ...options.map((o) => PopupMenuItem<String>(value: o, child: Text(o))),
      ],
      child: FilterChipView.buildRaw(
        context,
        colors,
        label: label,
        value: (current == null || current.isEmpty) ? null : current,
        icon: Icons.filter_list_rounded,
      ),
    );
  }
}

/// A free-form key/value filter chip for arbitrary extra filters (party id,
/// GST registration type, branch, warehouse). Writes into [ApexTableController]
/// via [keyName].
class ApexValueFilter extends StatelessWidget {
  const ApexValueFilter({
    super.key,
    required this.controller,
    required this.keyName,
    required this.options,
    required this.toLabel,
    this.label,
  });

  final ApexTableController controller;
  final String keyName;
  final List<String> options;
  final String Function(String) toLabel;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final current = controller.value.activeFilters[keyName];
    return PopupMenuButton<String>(
      tooltip: label ?? keyName,
      onSelected: (v) => controller.setFilter(keyName, v.isEmpty ? null : v),
      itemBuilder: (_) => [
        const PopupMenuItem<String>(value: '', child: Text('All')),
        ...options.map(
          (o) => PopupMenuItem<String>(value: o, child: Text(toLabel(o))),
        ),
      ],
      child: FilterChipView.buildRaw(
        context,
        colors,
        label: label ?? keyName,
        value: current == null ? null : toLabel(current),
        icon: Icons.tune_rounded,
      ),
    );
  }
}
