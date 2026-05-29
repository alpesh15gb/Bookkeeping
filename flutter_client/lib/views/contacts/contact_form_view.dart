import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/contact_provider.dart';
import 'package:flutter_client/models/contact.dart';

class ContactFormView extends StatefulWidget {
  final ContactModel? contact;

  const ContactFormView({super.key, this.contact});

  @override
  State<ContactFormView> createState() => _ContactFormViewState();
}

class _ContactFormViewState extends State<ContactFormView> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _gstinController;
  late final TextEditingController _panController;
  late final TextEditingController _stateCodeController;
  late final TextEditingController _streetController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  late final TextEditingController _pincodeController;
  late final TextEditingController _countryController;

  String _contactType = 'CUSTOMER';
  String _registrationType = 'CONSUMER';

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _nameController = TextEditingController(text: c?.name ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _gstinController = TextEditingController(text: c?.gstin ?? '');
    _panController = TextEditingController(text: c?.pan ?? '');
    _stateCodeController = TextEditingController(text: c?.stateCode ?? '27');
    _contactType = c?.contactType ?? 'CUSTOMER';
    _registrationType = c?.registrationType ?? 'CONSUMER';

    final addr = c?.billingAddress ?? {};
    _streetController = TextEditingController(text: addr['street'] ?? '');
    _cityController = TextEditingController(text: addr['city'] ?? '');
    _stateController = TextEditingController(text: addr['state'] ?? '');
    _pincodeController = TextEditingController(text: addr['pincode'] ?? '');
    _countryController = TextEditingController(text: addr['country'] ?? 'India');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _gstinController.dispose();
    _panController.dispose();
    _stateCodeController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  void _save() async {
    if (_formKey.currentState!.validate()) {
      final billingAddr = {
        'street': _streetController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim(),
        'state_code': _stateCodeController.text.trim(),
        'pincode': _pincodeController.text.trim(),
        'country': _countryController.text.trim(),
      };

      final contact = ContactModel(
        id: widget.contact?.id ?? '',
        name: _nameController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        contactType: _contactType,
        gstin: _gstinController.text.trim().isEmpty ? null : _gstinController.text.toUpperCase().trim(),
        pan: _panController.text.trim().isEmpty ? null : _panController.text.toUpperCase().trim(),
        registrationType: _registrationType,
        billingAddress: billingAddr,
        stateCode: _stateCodeController.text.trim(),
        isActive: widget.contact?.isActive ?? true,
      );

      final provider = context.read<ContactProvider>();
      bool success;
      if (widget.contact == null) {
        success = await provider.addContact(contact);
      } else {
        success = await provider.updateContact(widget.contact!.id, contact);
      }

      if (success && mounted) {
        Navigator.pop(context);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Operation failed'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.brandNavy,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      widget.contact == null ? Icons.person_add_rounded : Icons.edit_rounded,
                      size: 18,
                      color: AppColors.goldAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.contact == null ? 'Add Party' : 'Edit Party',
                    style: AppTextStyles.h2,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Contact Type
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.borderLight,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _TypeOptionBtn(
                                label: 'Customer',
                                value: 'CUSTOMER',
                                selected: _contactType == 'CUSTOMER',
                                onTap: () => setState(() => _contactType = 'CUSTOMER'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _TypeOptionBtn(
                                label: 'Vendor',
                                value: 'VENDOR',
                                selected: _contactType == 'VENDOR',
                                onTap: () => setState(() => _contactType = 'VENDOR'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Name
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name *',
                          hintText: 'Enter party name',
                          prefixIcon: Icon(Icons.person_outlined, size: 18),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Phone + Email
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Phone',
                                prefixIcon: Icon(Icons.phone_outlined, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // GSTIN + PAN + State Code
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _gstinController,
                              decoration: const InputDecoration(
                                labelText: 'GSTIN',
                                prefixIcon: Icon(Icons.pin_outlined, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _panController,
                              decoration: const InputDecoration(
                                labelText: 'PAN',
                                prefixIcon: Icon(Icons.credit_card_outlined, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _stateCodeController,
                              decoration: const InputDecoration(labelText: 'State Code *'),
                              maxLength: 2,
                              validator: (v) => (v == null || v.length != 2) ? '2 chars' : null,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Billing Address Section
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        decoration: BoxDecoration(
                          color: AppColors.borderLight,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Text('BILLING ADDRESS', style: AppTextStyles.labelSmall),
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _streetController,
                        decoration: const InputDecoration(
                          labelText: 'Street *',
                          prefixIcon: Icon(Icons.location_on_outlined, size: 18),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Street is required' : null,
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _cityController,
                              decoration: const InputDecoration(labelText: 'City *'),
                              validator: (v) => (v == null || v.isEmpty) ? 'City is required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _stateController,
                              decoration: const InputDecoration(labelText: 'State *'),
                              validator: (v) => (v == null || v.isEmpty) ? 'State is required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _pincodeController,
                              decoration: const InputDecoration(labelText: 'Pincode *'),
                              validator: (v) => (v == null || v.isEmpty) ? 'Pincode is required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _countryController,
                              decoration: const InputDecoration(labelText: 'Country *'),
                              validator: (v) => (v == null || v.isEmpty) ? 'Country is required' : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _save,
                    child: Text(widget.contact == null ? 'Create' : 'Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeOptionBtn extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _TypeOptionBtn({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.bgSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? AppColors.brandNavy : AppColors.borderInput,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected ? AppShadows.card : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
