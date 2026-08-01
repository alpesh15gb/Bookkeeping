/// Unified filter bar component — search + status chips + date range + type filter.
///
/// Replaces ad-hoc filter implementations across all list screens.
/// Every list screen should use this instead of building its own search/filter row.
library;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/responsive.dart';

/// A single filter chip option.
class FilterChipOption {
  const FilterChipOption(this.label, this.value);
  final String label;
  final String? value;
}

/// Callback contract for filter changes.
class FilterState {
  const FilterState({
    this.search = '',
    this.status,
    this.dateFrom,
    this.dateTo,
    this.type,
  });

  final String search;
  final String? status;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? type;

  bool get hasActiveFilters =>
      search.isNotEmpty ||
      status != null ||
      dateFrom != null ||
      dateTo != null ||
      type != null;

  FilterState copyWith({
    String? search,
    String? status,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? type,
    bool clearSearch = false,
    bool clearStatus = false,
    bool clearDates = false,
    bool clearType = false,
  }) {
    return FilterState(
      search: clearSearch ? '' : (search ?? this.search),
      status: clearStatus ? null : (status ?? this.status),
      dateFrom: clearDates ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDates ? null : (dateTo ?? this.dateTo),
      type: clearType ? null : (type ?? this.type),
    );
  }
}

class DateRange {
  const DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

/// Unified filter bar with search, status chips, type filter, and date range.
class ApexFilterBar extends StatelessWidget {
  const ApexFilterBar({
    super.key,
    required this.state,
    required this.onChanged,
    this.statusOptions = const [],
    this.typeOptions = const [],
    this.searchHint = 'Search…',
    this.showDateFilter = false,
    this.dateLabel = 'Period',
  });

  final FilterState state;
  final ValueChanged<FilterState> onChanged;
  final List<FilterChipOption> statusOptions;
  final List<FilterChipOption> typeOptions;
  final String searchHint;
  final bool showDateFilter;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SearchField(
            value: state.search,
            hint: searchHint,
            onChanged: (v) => onChanged(state.copyWith(search: v)),
          ),
          if (statusOptions.isNotEmpty) ...[
            const SizedBox(height: 8),
            _StatusChips(
              options: statusOptions,
              selected: state.status,
              onSelected: (v) => onChanged(
                state.copyWith(
                  status: v,
                  clearStatus: v == null && state.status != null
                      ? false
                      : false,
                ),
              ),
            ),
          ],
          if (showDateFilter) ...[
            const SizedBox(height: 8),
            _DateRangeChip(
              dateFrom: state.dateFrom,
              dateTo: state.dateTo,
              label: dateLabel,
              colors: colors,
              onChanged: (from, to) =>
                  onChanged(state.copyWith(dateFrom: from, dateTo: to)),
              onClear: () => onChanged(state.copyWith(clearDates: true)),
            ),
          ],
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _SearchField(
            value: state.search,
            hint: searchHint,
            onChanged: (v) => onChanged(state.copyWith(search: v)),
          ),
        ),
        if (statusOptions.isNotEmpty) ...[
          const SizedBox(width: 12),
          _StatusChips(
            options: statusOptions,
            selected: state.status,
            onSelected: (v) => onChanged(state.copyWith(status: v)),
          ),
        ],
        if (showDateFilter) ...[
          const SizedBox(width: 12),
          _DateRangeChip(
            dateFrom: state.dateFrom,
            dateTo: state.dateTo,
            label: dateLabel,
            colors: colors,
            onChanged: (from, to) =>
                onChanged(state.copyWith(dateFrom: from, dateTo: to)),
            onClear: () => onChanged(state.copyWith(clearDates: true)),
          ),
        ],
        if (state.hasActiveFilters)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: TextButton.icon(
              onPressed: () => onChanged(const FilterState()),
              icon: const Icon(Icons.clear_rounded, size: 16),
              label: Text(ResponsiveLayout.isMobile(context) ? '' : 'Clear'),
            ),
          ),
      ],
    );
  }
}

// ── Private sub-widgets ──────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  final String value;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final controller = TextEditingController(text: value);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: colors.textMuted,
        ),
        suffixIcon: value.isNotEmpty
            ? IconButton(
                icon: Icon(
                  Icons.clear_rounded,
                  size: 16,
                  color: colors.textMuted,
                ),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ApexRadius.md),
          borderSide: BorderSide(color: colors.border),
        ),
      ),
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<FilterChipOption> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(ApexRadius.md),
          border: Border.all(color: colors.border),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: options.map((o) {
            final sel = selected == o.value;
            return GestureDetector(
              onTap: () => onSelected(sel ? null : o.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: sel ? colors.surfaceRaised : Colors.transparent,
                  borderRadius: BorderRadius.circular(ApexRadius.sm),
                  boxShadow: sel
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  o.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? colors.primary : colors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _DateRangeChip extends StatelessWidget {
  const _DateRangeChip({
    required this.dateFrom,
    required this.dateTo,
    required this.label,
    required this.colors,
    required this.onChanged,
    required this.onClear,
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String label;
  final ApexColors colors;
  final void Function(DateTime?, DateTime?) onChanged;
  final VoidCallback onClear;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final hasRange = dateFrom != null && dateTo != null;
    final labelText = hasRange
        ? '${_fmt(dateFrom!)} – ${_fmt(dateTo!)}'
        : label;

    return InkWell(
      borderRadius: BorderRadius.circular(ApexRadius.md),
      onTap: () => _showDatePicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(ApexRadius.md),
          border: Border.all(color: hasRange ? colors.primary : colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.date_range_rounded,
              size: 16,
              color: hasRange ? colors.primary : colors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              labelText,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: hasRange ? FontWeight.w600 : FontWeight.w500,
                color: hasRange ? colors.primary : colors.textSecondary,
              ),
            ),
            if (hasRange) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: colors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showDatePicker(BuildContext context) async {
    final from = dateFrom ?? DateTime.now().subtract(const Duration(days: 30));
    final to = dateTo ?? DateTime.now();

    final picked = await showDialog<DateRange>(
      context: context,
      builder: (ctx) => _DateRangePickerDialog(
        initialFrom: from,
        initialTo: to,
        colors: colors,
      ),
    );

    if (picked != null && context.mounted) {
      onChanged(picked.start, picked.end);
    }
  }
}

/// Inline date range picker dialog with presets.
class _DateRangePickerDialog extends StatefulWidget {
  const _DateRangePickerDialog({
    required this.initialFrom,
    required this.initialTo,
    required this.colors,
  });

  final DateTime initialFrom;
  final DateTime initialTo;
  final ApexColors colors;

  @override
  State<_DateRangePickerDialog> createState() => _DateRangePickerDialogState();
}

class _DateRangePickerDialogState extends State<_DateRangePickerDialog> {
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    _from = widget.initialFrom;
    _to = widget.initialTo;
  }

  static const List<(String, int)> _presets = [
    // label, days back from today
    ('Today', 0),
    ('This Week', 7),
    ('This Month', 30),
    ('This Quarter', 90),
    ('This Year', 365),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Period'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Presets
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.map((p) {
                final days = p.$2;
                final now = DateTime.now();
                final from = DateTime(
                  now.year,
                  now.month,
                  now.day,
                ).subtract(Duration(days: days));
                final to = now;
                final active = _from == from && _to == to;
                return ChoiceChip(
                  label: Text(p.$1, style: const TextStyle(fontSize: 12)),
                  selected: active,
                  onSelected: (_) => setState(() {
                    _from = from;
                    _to = to;
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Custom range
            Row(
              children: [
                Expanded(
                  child: _dateField(
                    'From',
                    _from,
                    (d) => setState(() => _from = d),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dateField('To', _to, (d) => setState(() => _to = d)),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, DateRange(start: _from, end: _to)),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _dateField(
    String label,
    DateTime value,
    ValueChanged<DateTime> onChanged,
  ) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
        ),
        child: Text(
          '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}
