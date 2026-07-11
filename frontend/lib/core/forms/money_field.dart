/// Specialized numeric form fields: money, GSTIN, percentage. Each implements
/// [ApexFormField] and registers with the nearest [ApexFormController].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../theme/responsive.dart';
import 'apex_form.dart';

void _registerField(BuildContext context, ApexFormField<dynamic> field) {
  context.findAncestorWidgetOfExactType<ApexForm>()?.controller.register(field);
}

/// A money field that formats input as Indian currency and parses to [double].
class ApexMoneyField extends StatefulWidget implements ApexFormField<double> {
  ApexMoneyField({
    super.key,
    required this.name,
    required this.label,
    this.initialValue,
    this.validator,
    this.enabled = true,
    this.allowNegative = false,
    this.onChanged,
  }) : _controller = TextEditingController(
         text: initialValue == null ? '' : initialValue.toStringAsFixed(2),
       );

  @override
  final String name;
  final double? initialValue;
  final String label;
  final bool enabled;
  final bool allowNegative;
  final String? Function(double?)? validator;
  final ValueChanged<double?>? onChanged;
  final TextEditingController _controller;

  @override
  double? get value => double.tryParse(_controller.text);
  @override
  String? validate() => validator?.call(value);

  @override
  State<ApexMoneyField> createState() => _ApexMoneyFieldState();
}

class _ApexMoneyFieldState extends State<ApexMoneyField> {
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
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(
            widget.allowNegative
                ? r'^-?[0-9]*\.?[0-9]{0,4}$'
                : r'^[0-9]*\.?[0-9]{0,4}$',
          ),
        ),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Text(
          '  ${AppConstants.currencySymbol} ',
          style: TextStyle(fontSize: 16),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: isMobile ? 16 : 14,
        ),
      ),
      onChanged: (v) => widget.onChanged?.call(double.tryParse(v)),
      validator: (_) => widget.validator?.call(widget.value),
    );
  }
}
