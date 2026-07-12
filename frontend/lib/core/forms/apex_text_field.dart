/// A generic text form field implementing [ApexFormField<String>].
/// Used for name, email, phone, address, and any other free-text input.
library;

import 'package:flutter/material.dart';

import 'apex_form.dart';

/// Helper that registers a field with the nearest [ApexForm] controller.
void _registerField(BuildContext context, ApexFormField<dynamic> field) {
  context.findAncestorWidgetOfExactType<ApexForm>()?.controller.register(field);
}

/// A text input implementing [ApexFormField].
// ignore: must_be_immutable
class ApexTextField extends StatefulWidget implements ApexFormField<String> {
  ApexTextField({
    super.key,
    required this.name,
    required this.label,
    this.initialValue,
    this.validator,
    this.enabled = true,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.textCapitalization,
    this.hintText,
    this.prefixIcon,
    this.onChanged,
  }) : _controller = TextEditingController(text: initialValue ?? '');

  @override
  final String name;
  final String? initialValue;
  final String label;
  final String? hintText;
  final IconData? prefixIcon;
  final bool enabled;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextCapitalization? textCapitalization;
  final String? Function(String?)? validator;
  final ValueChanged<String?>? onChanged;
  final TextEditingController _controller;

  @override
  String? get value =>
      _controller.text.trim().isEmpty ? null : _controller.text.trim();

  @override
  String? validate() => validator?.call(value);

  @override
  State<ApexTextField> createState() => _ApexTextFieldState();
}

class _ApexTextFieldState extends State<ApexTextField> {
  @override
  void initState() {
    super.initState();
    _registerField(context, widget);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget._controller,
      enabled: widget.enabled,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization ?? TextCapitalization.none,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        prefixIcon: widget.prefixIcon != null ? Icon(widget.prefixIcon) : null,
        counterText: widget.maxLength != null ? null : '',
      ),
      onChanged: widget.onChanged,
      validator: (_) => widget.validate(),
    );
  }
}
