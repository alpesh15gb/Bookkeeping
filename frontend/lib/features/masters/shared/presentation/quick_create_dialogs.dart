import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/features/masters/contacts/data/models/contact.dart';
import 'package:apexbooks/features/masters/contacts/presentation/contact_controller.dart';
import 'package:apexbooks/features/masters/products/data/models/product.dart';
import 'package:apexbooks/features/masters/products/presentation/product_controller.dart';

Future<Contact?> showQuickCreateParty(
  BuildContext context, {
  required ContactType contactType,
  String initialName = '',
}) {
  return showDialog<Contact>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _QuickPartyDialog(initialName: initialName, initialType: contactType),
  );
}

Future<Product?> showQuickCreateItem(
  BuildContext context, {
  String initialName = '',
  bool purchaseContext = false,
}) {
  return showDialog<Product>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _QuickItemDialog(
      initialName: initialName,
      purchaseContext: purchaseContext,
    ),
  );
}

class _QuickPartyDialog extends ConsumerStatefulWidget {
  const _QuickPartyDialog({
    required this.initialName,
    required this.initialType,
  });

  final String initialName;
  final ContactType initialType;

  @override
  ConsumerState<_QuickPartyDialog> createState() => _QuickPartyDialogState();
}

class _QuickPartyDialogState extends ConsumerState<_QuickPartyDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _phone = TextEditingController();
  final _gstin = TextEditingController();
  late ContactType _type;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName.trim());
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _gstin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final gstin = _gstin.text.trim().toUpperCase();
    final contact = Contact(
      id: '',
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      contactType: _type,
      gstin: gstin.isEmpty ? null : gstin,
      pan: gstin.isEmpty ? null : gstin.substring(2, 12),
      stateCode: gstin.isEmpty ? null : gstin.substring(0, 2),
      registrationType: gstin.isEmpty
          ? RegistrationType.unregistered
          : RegistrationType.regular,
    );
    final result = await ref
        .read(contactRepositoryProvider)
        .create(contact.toJson());
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        await ref
            .read(contactControllerProvider.notifier)
            .load(
              ListQuery(limit: 100, extra: {'contact_type': _type.apiValue}),
            );
        if (mounted) Navigator.of(context).pop(value);
      case Failure(:final error):
        setState(() {
          _saving = false;
          _error = error.message;
        });
      default:
        setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
      },
      child: AlertDialog(
        title: Text(
          'New ${widget.initialType == ContactType.vendor ? 'Vendor' : 'Customer'}',
        ),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                if (_error != null) ...[
                  _InlineError(_error!),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Party name *'),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Party name is required.'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Phone'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<ContactType>(
                        initialValue: _type,
                        decoration: const InputDecoration(labelText: 'Use as'),
                        items: ContactType.values
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type.displayLabel),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _type = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _gstin,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                    LengthLimitingTextInputFormatter(15),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'GSTIN (optional)',
                    helperText: 'State and PAN are derived automatically.',
                  ),
                  validator: (value) {
                    final text = value?.trim().toUpperCase() ?? '';
                    if (text.isEmpty) return null;
                    return RegExp(
                          r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
                        ).hasMatch(text)
                        ? null
                        : 'Enter a valid 15-character GSTIN.';
                  },
                  onFieldSubmitted: (_) => _save(),
                ),
              ],
            ),
          ),
        ),
      ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: const Text('Create & select  Ctrl+Enter'),
          ),
        ],
      ),
    );
  }
}

class _QuickItemDialog extends ConsumerStatefulWidget {
  const _QuickItemDialog({
    required this.initialName,
    required this.purchaseContext,
  });

  final String initialName;
  final bool purchaseContext;

  @override
  ConsumerState<_QuickItemDialog> createState() => _QuickItemDialogState();
}

class _QuickItemDialogState extends ConsumerState<_QuickItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _hsn = TextEditingController();
  final _uom = TextEditingController(text: 'PCS');
  final _salesPrice = TextEditingController();
  final _purchasePrice = TextEditingController();
  ProductType _type = ProductType.goods;
  double _gstRate = 18;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName.trim());
  }

  @override
  void dispose() {
    _name.dispose();
    _hsn.dispose();
    _uom.dispose();
    _salesPrice.dispose();
    _purchasePrice.dispose();
    super.dispose();
  }

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final product = Product(
      id: '',
      name: _name.text.trim(),
      hsnSac: _hsn.text.trim(),
      productType: _type,
      uom: _type == ProductType.service
          ? 'NOS'
          : _uom.text.trim().toUpperCase(),
      salesPrice: _number(_salesPrice),
      purchasePrice: _number(_purchasePrice),
      gstRate: _gstRate,
    );
    final result = await ref
        .read(productRepositoryProvider)
        .create(product.toJson());
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        await ref
            .read(productControllerProvider.notifier)
            .load(const ListQuery(limit: 100));
        if (mounted) Navigator.of(context).pop(value);
      case Failure(:final error):
        setState(() {
          _saving = false;
          _error = error.message;
        });
      default:
        setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
      },
      child: AlertDialog(
        title: const Text('New Item'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null) ...[
                    _InlineError(_error!),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _name,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Item name *'),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Item name is required.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<ProductType>(
                          initialValue: _type,
                          decoration: const InputDecoration(labelText: 'Type'),
                          items: ProductType.values
                              .map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type.displayLabel),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) setState(() => _type = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _hsn,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(8),
                          ],
                          decoration: InputDecoration(
                            labelText: _type == ProductType.service
                                ? 'SAC code *'
                                : 'HSN code *',
                          ),
                          validator: (value) =>
                              RegExp(
                                r'^[0-9]{6,8}$',
                              ).hasMatch(value?.trim() ?? '')
                              ? null
                              : 'Enter 6–8 digits.',
                        ),
                      ),
                      if (_type == ProductType.goods) ...[
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: _uom,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Unit *',
                            ),
                            validator: (value) =>
                                (value?.trim().isEmpty ?? true)
                                ? 'Required'
                                : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _salesPrice,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Sales rate',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _purchasePrice,
                          autofocus: widget.purchaseContext,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Purchase rate',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<double>(
                          initialValue: _gstRate,
                          decoration: const InputDecoration(
                            labelText: 'GST rate',
                          ),
                          items:
                              const [
                                    0.0,
                                    0.1,
                                    0.25,
                                    1.5,
                                    3.0,
                                    5.0,
                                    6.0,
                                    7.5,
                                    12.0,
                                    18.0,
                                    28.0,
                                  ]
                                  .map(
                                    (rate) => DropdownMenuItem(
                                      value: rate,
                                      child: Text(
                                        '${rate.toString().replaceFirst(RegExp(r'\.0$'), '')}%',
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            if (value != null) setState(() => _gstRate = value);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: const Text('Create & select  Ctrl+Enter'),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}
