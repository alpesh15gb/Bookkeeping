import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/responsive.dart';
import '../utils/formatters.dart';
import 'apex_form.dart';

void _registerField(BuildContext context, ApexFormField<dynamic> field) {
  context.findAncestorWidgetOfExactType<ApexForm>()?.controller.register(field);
}

/// A GST field that upper-cases input and validates the GSTIN pattern.
class ApexGSTField extends StatefulWidget implements ApexFormField<String> {
  ApexGSTField({
    super.key,
    required this.name,
    required this.label,
    this.initialValue,
    this.enabled = true,
    this.onChanged,
  }) : _controller = TextEditingController(text: initialValue ?? '');

  @override
  final String name;
  final String? initialValue;
  final String label;
  final bool enabled;
  final ValueChanged<String?>? onChanged;
  final TextEditingController _controller;

  @override
  String? get value =>
      _controller.text.trim().isEmpty ? null : _controller.text.trim();
  @override
  String? validate() => gstinValidator(value);

  @override
  State<ApexGSTField> createState() => _ApexGSTFieldState();
}

class _ApexGSTFieldState extends State<ApexGSTField> {
  @override
  void initState() {
    super.initState();
    _registerField(context, widget);
    widget._controller.addListener(() {
      final upper = widget._controller.text.toUpperCase();
      if (widget._controller.text != upper) {
        widget._controller.value = TextEditingValue(
          text: upper,
          selection: TextSelection.collapsed(offset: upper.length),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget._controller,
      enabled: widget.enabled,
      textCapitalization: TextCapitalization.characters,
      maxLength: 15,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.receipt_long_outlined),
        counterText: '',
      ),
      onChanged: widget.onChanged,
      validator: (_) => widget.validate(),
    );
  }
}

/// A percentage field constrained to 0-100 with up to 2 decimals.
class ApexPercentageField extends StatefulWidget
    implements ApexFormField<double> {
  ApexPercentageField({
    super.key,
    required this.name,
    required this.label,
    this.initialValue,
    this.enabled = true,
    this.onChanged,
  }) : _controller = TextEditingController(
         text: initialValue == null ? '' : initialValue.toStringAsFixed(2),
       );

  @override
  final String name;
  final double? initialValue;
  final String label;
  final bool enabled;
  final ValueChanged<double?>? onChanged;
  final TextEditingController _controller;

  @override
  double? get value => double.tryParse(_controller.text);
  @override
  String? validate() {
    final v = value;
    if (v == null) return null;
    if (v < 0 || v > 100) return 'Enter a value between 0 and 100';
    return null;
  }

  @override
  State<ApexPercentageField> createState() => _ApexPercentageFieldState();
}

class _ApexPercentageFieldState extends State<ApexPercentageField> {
  @override
  void initState() {
    super.initState();
    _registerField(context, widget);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return TextFormField(
      controller: widget._controller,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^[0-9]*\.?[0-9]{0,2}$')),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Text('  % ', style: TextStyle(fontSize: 16)),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: isMobile ? 16 : 14,
        ),
      ),
      onChanged: (v) => widget.onChanged?.call(double.tryParse(v)),
      validator: (_) => widget.validate(),
    );
  }
}
