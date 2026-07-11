/// The raw filter chip pill + the date-range filter chip. Shared rendering
/// for all [ApexTableController]-backed filters.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'table_controller.dart';

/// Internal helper rendering the chip pill shared by all filters.
class FilterChipView {
  FilterChipView._();

  static Widget buildRaw(
    BuildContext context,
    ApexColors colors, {
    required String label,
    String? value,
    IconData? icon,
    VoidCallback? onClear,
  }) {
    final active = value != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? colors.primaryContainer : colors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(
              icon,
              size: 16,
              color: active ? colors.primary : colors.textSecondary,
            ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          if (active) ...[
            const SizedBox(width: 6),
            Text(
              ': $value',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A date-range filter chip that opens a range picker.
class ApexDateRangeFilter extends StatefulWidget {
  const ApexDateRangeFilter({
    super.key,
    required this.controller,
    this.label = 'Date range',
  });

  final ApexTableController controller;
  final String label;

  @override
  State<ApexDateRangeFilter> createState() => _ApexDateRangeFilterState();
}

class _ApexDateRangeFilterState extends State<ApexDateRangeFilter> {
  Future<void> _pick() async {
    final now = DateTime.now();
    final initial =
        widget.controller.value.dateFrom != null &&
            widget.controller.value.dateTo != null
        ? DateTimeRange(
            start: widget.controller.value.dateFrom!,
            end: widget.controller.value.dateTo!,
          )
        : DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: initial,
    );
    if (picked != null)
      widget.controller.setDateRange(picked.start, picked.end);
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final from = widget.controller.value.dateFrom;
    final to = widget.controller.value.dateTo;
    final hasRange = from != null && to != null;
    final value = hasRange ? '${formatDate(from)} → ${formatDate(to)}' : null;
    return InkWell(
      onTap: _pick,
      borderRadius: BorderRadius.circular(999),
      child: FilterChipView.buildRaw(
        context,
        colors,
        label: widget.label,
        value: value,
        icon: Icons.date_range_rounded,
        onClear: hasRange
            ? () => widget.controller.setDateRange(null, null)
            : null,
      ),
    );
  }
}
