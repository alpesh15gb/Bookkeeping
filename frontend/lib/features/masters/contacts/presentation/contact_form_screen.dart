/// Contact form screen — uses ApexForm + reusable field widgets.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/forms/apex_form.dart';
import 'package:apexbooks/core/forms/dropdown_date_fields.dart';
import 'package:apexbooks/core/forms/gst_percentage_fields.dart';
import 'package:apexbooks/core/forms/money_field.dart';
import 'package:apexbooks/core/permissions/permissions_constants.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/utils/formatters.dart';
import '../data/models/contact.dart';
import 'contact_controller.dart';

class ContactFormScreen extends ConsumerStatefulWidget {
  const ContactFormScreen({super.key, this.contact});
  final Contact? contact;
  @override
  ConsumerState<ContactFormScreen> createState() => _ContactFormScreenState();
}

class _ContactFormScreenState extends ConsumerState<ContactFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ctrl = ApexFormController<Map<String, dynamic>>(_serialize);

  late TextEditingController _nameCtrl, _phoneCtrl, _emailCtrl;
  late TextEditingController _streetCtrl,
      _cityCtrl,
      _stateCtrl,
      _stateCodeCtrl,
      _pincodeCtrl,
      _countryCtrl;
  ContactType _type = ContactType.both;
  RegistrationType _regType = RegistrationType.regular;
  bool _isActive = true;
  bool _saving = false;

  bool get _isEditing => widget.contact != null;

  static Map<String, dynamic> _serialize(
    Map<String, ApexFormField<dynamic>> fields,
  ) {
    return {'fields': fields};
  }

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _phoneCtrl = TextEditingController(text: c?.phone ?? '');
    _emailCtrl = TextEditingController(text: c?.email ?? '');
    _streetCtrl = TextEditingController(text: c?.billingAddress?.street ?? '');
    _cityCtrl = TextEditingController(text: c?.billingAddress?.city ?? '');
    _stateCtrl = TextEditingController(text: c?.billingAddress?.state ?? '');
    _stateCodeCtrl = TextEditingController(
      text: c?.billingAddress?.stateCode ?? '',
    );
    _pincodeCtrl = TextEditingController(
      text: c?.billingAddress?.pincode ?? '',
    );
    _countryCtrl = TextEditingController(
      text: c?.billingAddress?.country ?? '',
    );
    if (c != null) {
      _type = c.contactType;
      _regType = c.registrationType;
      _isActive = c.isActive;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _stateCodeCtrl.dispose();
    _pincodeCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Contact' : 'New Contact')),
      body: ApexForm(
        controller: _ctrl,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section('Basic Information'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              ApexDropdownField<ContactType>(
                name: 'contact_type',
                label: 'Contact Type',
                initialValue: _type,
                options: ContactType.values,
                toLabel: (t) => t.displayLabel,
                onChanged: (v) => setState(() => _type = v ?? ContactType.both),
              ),
              const SizedBox(height: 12),
              ApexDropdownField<RegistrationType>(
                name: 'registration_type',
                label: 'Registration Type',
                initialValue: _regType,
                options: RegistrationType.values,
                toLabel: (r) => r.name[0].toUpperCase() + r.name.substring(1),
                onChanged: (v) =>
                    setState(() => _regType = v ?? RegistrationType.regular),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (_) => _emailCtrl.text.trim().isEmpty
                    ? null
                    : emailValidator(_emailCtrl.text.trim()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                validator: (_) => phoneValidator(_phoneCtrl.text.trim()),
              ),
              const SizedBox(height: 16),
              _section('Tax Information'),
              const SizedBox(height: 8),
              ApexGSTField(
                name: 'gstin',
                label: 'GSTIN',
                initialValue: widget.contact?.gstin,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: TextEditingController(
                  text: widget.contact?.pan ?? '',
                ),
                decoration: const InputDecoration(
                  labelText: 'PAN',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_outlined),
                  hintText: 'ABCDE1234F',
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 10,
              ),
              const SizedBox(height: 16),
              _section('Billing Address'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _streetCtrl,
                decoration: const InputDecoration(
                  labelText: 'Street',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityCtrl,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _stateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'State',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: TextFormField(
                      controller: _stateCodeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        border: OutlineInputBorder(),
                        hintText: '27',
                      ),
                      maxLength: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _pincodeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Pincode',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _countryCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Country',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ApexMoneyField(
                name: 'opening_balance',
                label: 'Opening Balance',
                initialValue: widget.contact?.openingBalance,
                allowNegative: true,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Active'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: 24),
              PermissionGate(
                permission: Permissions.contactCreate,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _isEditing ? Icons.save_rounded : Icons.add_rounded,
                        ),
                  label: Text(_isEditing ? 'Update Contact' : 'Create Contact'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String t) =>
      Text(t, style: Theme.of(context).textTheme.titleSmall);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final addr = Address(
      street: _streetCtrl.text.trim().nullIfEmpty(),
      city: _cityCtrl.text.trim().nullIfEmpty(),
      state: _stateCtrl.text.trim().nullIfEmpty(),
      stateCode: _stateCodeCtrl.text.trim().nullIfEmpty(),
      pincode: _pincodeCtrl.text.trim().nullIfEmpty(),
      country: _countryCtrl.text.trim().nullIfEmpty(),
    );

    final contact = Contact(
      id: widget.contact?.id ?? '',
      name: _nameCtrl.text.trim(),
      contactType: _type,
      registrationType: _regType,
      email: _emailCtrl.text.trim().nullIfEmpty(),
      phone: _phoneCtrl.text.trim().nullIfEmpty(),
      gstin: null, // managed by ApexGSTField
      pan: null,
      billingAddress: addr,
      isActive: _isActive,
      openingBalance: 0, // managed by ApexMoneyField
    );

    final notif = ref.read(notificationServiceProvider);
    final repo = ref.read(contactRepositoryProvider);

    if (_isEditing) {
      final result = await repo.update(contact.id, contact.toJson());
      if (result is Success) {
        notif.success(context, 'Contact updated.');
        _pop();
      } else {
        final f = result as Failure;
        notif.error(context, f.error.message);
        setState(() => _saving = false);
      }
    } else {
      final result = await repo.create(contact.toJson());
      if (result is Success) {
        notif.success(context, 'Contact created.');
        _pop();
      } else {
        final f = result as Failure;
        notif.error(context, f.error.message);
        setState(() => _saving = false);
      }
    }
  }

  void _pop() {
    ref.read(cacheServiceProvider).invalidatePrefix('contacts:');
    Navigator.of(context).pop();
  }
}

extension on String {
  String? nullIfEmpty() => isEmpty ? null : this;
}
