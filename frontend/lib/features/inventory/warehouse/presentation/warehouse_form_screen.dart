/// Warehouse create/edit form.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/dialogs/dialog_service.dart';
import 'package:apexbooks/core/result/result.dart';
import '../services/warehouse_service.dart';
import 'warehouse_providers.dart';

class WarehouseFormScreen extends ConsumerStatefulWidget {
  const WarehouseFormScreen({super.key, this.warehouse});

  /// When provided the form operates in edit mode.
  final Warehouse? warehouse;

  @override
  ConsumerState<WarehouseFormScreen> createState() =>
      _WarehouseFormScreenState();
}

class _WarehouseFormScreenState extends ConsumerState<WarehouseFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _codeCtrl;
  late TextEditingController _gstinCtrl;
  late TextEditingController _streetCtrl;
  late TextEditingController _cityCtrl;
  late TextEditingController _stateCtrl;
  late TextEditingController _pincodeCtrl;
  late TextEditingController _locationCtrl;
  bool _isActive = true;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.warehouse != null;

  bool get _hasUnsavedChanges {
    if (_isEditing) {
      final w = widget.warehouse!;
      return _nameCtrl.text != w.name ||
          _codeCtrl.text != w.code ||
          _gstinCtrl.text != (w.gstin ?? '') ||
          _streetCtrl.text != (w.address?.street ?? '') ||
          _cityCtrl.text != (w.address?.city ?? '') ||
          _stateCtrl.text != (w.address?.state ?? '') ||
          _pincodeCtrl.text != (w.address?.pincode ?? '') ||
          _locationCtrl.text != (w.location ?? '') ||
          _isActive != w.isActive;
    }
    return _nameCtrl.text.isNotEmpty ||
        _codeCtrl.text.isNotEmpty ||
        _gstinCtrl.text.isNotEmpty ||
        _streetCtrl.text.isNotEmpty ||
        _cityCtrl.text.isNotEmpty ||
        _stateCtrl.text.isNotEmpty ||
        _pincodeCtrl.text.isNotEmpty ||
        _locationCtrl.text.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    final w = widget.warehouse;
    _nameCtrl = TextEditingController(text: w?.name ?? '');
    _codeCtrl = TextEditingController(text: w?.code ?? '');
    _gstinCtrl = TextEditingController(text: w?.gstin ?? '');
    _streetCtrl = TextEditingController(text: w?.address?.street ?? '');
    _cityCtrl = TextEditingController(text: w?.address?.city ?? '');
    _stateCtrl = TextEditingController(text: w?.address?.state ?? '');
    _pincodeCtrl = TextEditingController(text: w?.address?.pincode ?? '');
    _locationCtrl = TextEditingController(text: w?.location ?? '');
    _isActive = w?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _gstinCtrl.dispose();
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final payload = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'code': _codeCtrl.text.trim(),
      'is_active': _isActive,
    };
    if (_gstinCtrl.text.trim().isNotEmpty) {
      payload['gstin'] = _gstinCtrl.text.trim();
    }
    if (_locationCtrl.text.trim().isNotEmpty) {
      payload['location'] = _locationCtrl.text.trim();
    }
    final addressParts = [
      _streetCtrl.text.trim(),
      _cityCtrl.text.trim(),
      _stateCtrl.text.trim(),
      _pincodeCtrl.text.trim(),
    ].where((p) => p.isNotEmpty).toList();
    if (addressParts.isNotEmpty) {
      payload['address'] = {
        if (_streetCtrl.text.trim().isNotEmpty)
          'street': _streetCtrl.text.trim(),
        if (_cityCtrl.text.trim().isNotEmpty) 'city': _cityCtrl.text.trim(),
        if (_stateCtrl.text.trim().isNotEmpty)
          'state': _stateCtrl.text.trim(),
        if (_pincodeCtrl.text.trim().isNotEmpty)
          'pincode': _pincodeCtrl.text.trim(),
      };
    }

    final service = ref.read(warehouseServiceProvider);
    final Result<Warehouse> result;
    if (_isEditing) {
      result = await service.update(widget.warehouse!.id, payload);
    } else {
      result = await service.create(payload);
    }

    if (!mounted) return;
    setState(() => _saving = false);

    switch (result) {
      case Success():
        ref.invalidate(warehouseListProvider);
        Navigator.of(context).pop();
      case Failure(:final error):
        setState(() => _error = error.message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${error.message}')),
        );
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (_hasUnsavedChanges) {
              final result =
                  await const DialogService().unsavedChanges(context);
              if (result == DialogResult.discard && context.mounted) {
                Navigator.of(context).pop();
              }
            } else if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            backgroundColor: colors.surfaceMuted,
            appBar: AppBar(
              backgroundColor: colors.surfaceRaised,
              elevation: 0,
              titleSpacing: 20,
              title: Text(
                _isEditing ? 'Edit Warehouse' : 'New Warehouse',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: colors.border),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 16,
                  ),
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: LoadingSpinner(size: 16),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(_isEditing ? 'Update' : 'Save'),
                  ),
                ),
              ],
            ),
            body: _buildBody(colors, isMobile),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ApexColors colors, bool isMobile) {
    if (_error != null) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            color: colors.danger.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 18, color: colors.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: colors.danger,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _formContent(colors, isMobile)),
        ],
      );
    }
    return _formContent(colors, isMobile);
  }

  Widget _formContent(ApexColors colors, bool isMobile) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.all(isMobile ? 12 : 24),
            children: [
              _section('Basic Information', colors),
              const SizedBox(height: 12),
              _labeled(
                'Warehouse Name',
                TextFormField(
                  controller: _nameCtrl,
                  decoration: _dec(colors,
                      hint: 'e.g. Main Warehouse, Godown A',
                      icon: Icons.warehouse_outlined),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                colors,
                required: true,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _labeled(
                      'Code',
                      TextFormField(
                        controller: _codeCtrl,
                        decoration: _dec(colors,
                            hint: 'e.g. WH-001',
                            icon: Icons.tag_rounded),
                      ),
                      colors,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _labeled(
                      'GSTIN',
                      TextFormField(
                        controller: _gstinCtrl,
                        decoration: _dec(colors,
                            hint: 'e.g. 27ABCDE1234F1Z5',
                            icon: Icons.badge_outlined),
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 15,
                      ),
                      colors,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _labeled(
                'Location Description',
                TextFormField(
                  controller: _locationCtrl,
                  decoration: _dec(colors,
                      hint: 'e.g. Ground floor, B-wing',
                      icon: Icons.location_on_outlined),
                ),
                colors,
              ),
              const SizedBox(height: 24),
              _section('Address', colors),
              const SizedBox(height: 12),
              _labeled(
                'Street',
                TextFormField(
                  controller: _streetCtrl,
                  decoration: _dec(colors,
                      hint: 'e.g. 42, MG Road',
                      icon: Icons.map_outlined),
                  maxLines: 2,
                ),
                colors,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _labeled(
                      'City',
                      TextFormField(
                        controller: _cityCtrl,
                        decoration:
                            _dec(colors, hint: 'e.g. Mumbai'),
                      ),
                      colors,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _labeled(
                      'State',
                      TextFormField(
                        controller: _stateCtrl,
                        decoration:
                            _dec(colors, hint: 'e.g. Maharashtra'),
                      ),
                      colors,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _labeled(
                      'Pincode',
                      TextFormField(
                        controller: _pincodeCtrl,
                        decoration: _dec(colors,
                            hint: 'e.g. 400001',
                            icon: Icons.numbers_outlined),
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                      ),
                      colors,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 24),
              _section('Settings', colors),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: BorderRadius.circular(ApexRadius.lg),
                  border: Border.all(color: colors.border),
                ),
                child: SwitchListTile(
                  title: Text(
                    'Active',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'Inactive warehouses cannot receive stock.',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _isEditing ? Icons.save_rounded : Icons.add_rounded,
                        size: 18,
                      ),
                label: Text(
                  _saving
                      ? 'Saving…'
                      : _isEditing
                          ? 'Update Warehouse'
                          : 'Create Warehouse',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String label, ApexColors colors) => Text(
    label.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: colors.textMuted,
    ),
  );

  Widget _labeled(
    String label,
    Widget field,
    ApexColors colors, {
    bool required = false,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (required)
                Text(
                  ' *',
                  style: TextStyle(
                    color: colors.danger,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          field,
        ],
      );
}

InputDecoration _dec(ApexColors colors, {String? hint, IconData? icon}) =>
    InputDecoration(
      isDense: true,
      hintText: hint,
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 18, color: colors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ApexRadius.sm),
      ),
      filled: true,
      fillColor: colors.surfaceRaised,
    );
