/// Specialized form fields (dropdown + date picker) implementing [ApexFormField]
/// and registering with an [ApexFormController].
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'apex_form.dart';

/// Helper that registers a field with the nearest [ApexForm] controller.
void _registerField(BuildContext context, ApexFormField<dynamic> field) {
  final ancestor = context.findAncestorWidgetOfExactType<ApexForm>();
  ancestor?.controller.register(field);
}

/// A dropdown field backed by a list of options.
// ignore: must_be_immutable
class ApexDropdownField<T> extends StatefulWidget implements ApexFormField<T> {
  ApexDropdownField({
    super.key,
    required this.name,
    required this.label,
    required this.options,
    required this.toLabel,
    this.initialValue,
    this.validator,
    this.enabled = true,
    this.hint,
    this.prefixIcon,
    this.onChanged,
  }) : _selected = initialValue;

  @override
  final String name;
  final T? initialValue;
  final String label;
  final String? hint;
  final List<T> options;
  final String Function(T) toLabel;
  final IconData? prefixIcon;
  final bool enabled;
  final String? Function(T?)? validator;
  final ValueChanged<T?>? onChanged;

  T? _selected;

  @override
  T? get value => _selected ?? initialValue;

  @override
  String? validate() => validator?.call(value);

  @override
  State<ApexDropdownField<T>> createState() => _ApexDropdownFieldState<T>();
}

class _ApexDropdownFieldState<T> extends State<ApexDropdownField<T>> {
  @override
  void initState() {
    super.initState();
    _registerField(context, widget);
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return DropdownButtonFormField<T>(
      initialValue: widget._selected,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: widget.prefixIcon != null ? Icon(widget.prefixIcon) : null,
      ),
      items: widget.options
          .map(
            (o) => DropdownMenuItem<T>(
              value: o,
              child: Text(
                widget.toLabel(o),
                style: TextStyle(color: colors.textPrimary),
              ),
            ),
          )
          .toList(),
      onChanged: widget.enabled
          ? (v) {
              setState(() => widget._selected = v);
              widget.onChanged?.call(v);
            }
          : null,
      validator: (_) => widget.validator?.call(widget.value),
    );
  }
}

/// A date-picker field that opens a native date picker on tap.
// ignore: must_be_immutable
class ApexDateField extends StatefulWidget implements ApexFormField<DateTime> {
  ApexDateField({
    super.key,
    required this.name,
    required this.label,
    this.initialValue,
    this.firstDate,
    this.lastDate,
    this.validator,
    this.enabled = true,
    this.onChanged,
  });

  @override
  final String name;
  final DateTime? initialValue;
  final String label;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool enabled;
  final String? Function(DateTime?)? validator;
  final ValueChanged<DateTime?>? onChanged;

  DateTime? _picked;

  @override
  DateTime? get value => _picked ?? initialValue;

  @override
  String? validate() => validator?.call(value);

  @override
  State<ApexDateField> createState() => _ApexDateFieldState();
}

class _ApexDateFieldState extends State<ApexDateField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    widget._picked = widget.value;
    _controller = TextEditingController(
      text: widget.value == null ? '' : formatDate(widget.value!),
    );
    _registerField(context, widget);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (!widget.enabled) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.value ?? DateTime.now(),
      firstDate: widget.firstDate ?? DateTime(2000),
      lastDate: widget.lastDate ?? DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        widget._picked = picked;
        _controller.text = formatDate(picked);
      });
      widget.onChanged?.call(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      readOnly: true,
      enabled: widget.enabled,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.calendar_today_outlined),
        suffixIcon: Icon(Icons.event_outlined),
      ),
      onTap: _pick,
      validator: (_) => widget.validator?.call(widget.value),
    );
  }
}
