/// Generic form framework. [ApexForm] wraps a [Form] and tracks dirty/valid
/// state; [ApexFormField] is the base contract for all typed fields. Specialized
/// fields (dropdown, date, money, GST, percentage) live alongside and compose
/// the validators from `core/utils/formatters.dart`.
library;

import 'package:flutter/material.dart';

/// The base contract for every form field in the ApexBooks app. Concrete
/// fields expose their current value and a validator so [ApexForm] can run
/// validation and produce a typed payload.
abstract class ApexFormField<T> {
  /// The field's key in the serialized payload.
  String get name;

  /// The current value (may be null for optional/empty fields).
  T? get value;

  /// Validates the current value; returns an error message or `null` when ok.
  String? validate();
}

/// A stateful form wrapper that:
///   * runs validation across all registered [ApexFormField]s,
/// * exposes a typed payload via [submit],
/// * tracks a dirty flag for unsaved-changes guards.
class ApexFormController<T> extends ChangeNotifier {
  ApexFormController(this._serializer);

  final Map<String, dynamic> Function(Map<String, ApexFormField<dynamic>>)
  _serializer;
  final _fields = <String, ApexFormField<dynamic>>{};
  bool _dirty = false;

  /// Registers a field (called from field widgets during build).
  void register(ApexFormField<dynamic> field) => _fields[field.name] = field;

  /// Whether any field has been edited since the last reset.
  bool get isDirty => _dirty;
  void markDirty() {
    if (!_dirty) {
      _dirty = true;
      notifyListeners();
    }
  }

  void resetDirty() {
    _dirty = false;
    notifyListeners();
  }

  /// Validates every field. Returns `true` when all pass.
  bool validate() => _fields.values.every((f) => f.validate() == null);

  /// Validates and, if ok, builds the payload via the serializer.
  Map<String, dynamic>? submit() {
    if (!validate()) return null;
    return _serializer(_fields);
  }

  /// The raw field registry (read-only view for serializers).
  Map<String, ApexFormField<dynamic>> get fields => Map.unmodifiable(_fields);
}

/// A widget that binds an [ApexFormController] and rebuilds children inside a
/// [Form]. Fields register themselves with the controller via [register].
class ApexForm extends StatefulWidget {
  const ApexForm({
    super.key,
    required this.controller,
    required this.child,
    this.onChanged,
  });

  final ApexFormController<dynamic> controller;
  final Widget child;
  final VoidCallback? onChanged;

  @override
  State<ApexForm> createState() => _ApexFormState();
}

class _ApexFormState extends State<ApexForm> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    if (mounted) setState(() {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Form(child: widget.child);
  }
}
