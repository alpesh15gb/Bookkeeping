import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/models/contact.dart';
import 'package:flutter_client/providers/contact_provider.dart';

// ── GSTIN → State code (first 2 digits) ─────────────────────────────────────
const Map<String, String> _gstinStateCodeMap = {
  '01': '01', '02': '02', '03': '03', '04': '04', '05': '05',
  '06': '06', '07': '07', '08': '08', '09': '09', '10': '10',
  '11': '11', '12': '12', '13': '13', '14': '14', '15': '15',
  '16': '16', '17': '17', '18': '18', '19': '19', '20': '20',
  '21': '21', '22': '22', '23': '23', '24': '24', '25': '25',
  '26': '26', '27': '27', '28': '28', '29': '29', '30': '30',
  '31': '31', '32': '32', '33': '33', '34': '34', '35': '35',
  '36': '36', '37': '37', '38': '38',
};

const Map<String, String> _stateNames = {
  '01': 'J&K',             '02': 'Himachal Pradesh',  '03': 'Punjab',
  '04': 'Chandigarh',      '05': 'Uttarakhand',        '06': 'Haryana',
  '07': 'Delhi',           '08': 'Rajasthan',          '09': 'Uttar Pradesh',
  '10': 'Bihar',           '11': 'Sikkim',             '12': 'Arunachal Pradesh',
  '13': 'Nagaland',        '14': 'Manipur',            '15': 'Mizoram',
  '16': 'Tripura',         '17': 'Meghalaya',          '18': 'Assam',
  '19': 'West Bengal',     '20': 'Jharkhand',          '21': 'Odisha',
  '22': 'Chhattisgarh',    '23': 'Madhya Pradesh',     '24': 'Gujarat',
  '25': 'Daman & Diu',     '26': 'Dadra & NH',         '27': 'Maharashtra',
  '28': 'Andhra Pradesh',  '29': 'Karnataka',          '30': 'Goa',
  '31': 'Lakshadweep',     '32': 'Kerala',             '33': 'Tamil Nadu',
  '34': 'Puducherry',      '35': 'A&N Islands',        '36': 'Telangana',
  '37': 'Andhra Pradesh',  '38': 'Ladakh',
};

/// Shows a bottom sheet to quickly create a customer or vendor.
/// Returns the created [ContactModel] on success, or null if cancelled.
Future<ContactModel?> showQuickCreateCustomer(
  BuildContext context, {
  String? initialName,
  String contactType = 'CUSTOMER',
}) {
  return showModalBottomSheet<ContactModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuickCreateCustomerSheet(initialName: initialName, contactType: contactType),
  );
}

class _QuickCreateCustomerSheet extends StatefulWidget {
  final String? initialName;
  final String contactType;
  const _QuickCreateCustomerSheet({this.initialName, this.contactType = 'CUSTOMER'});

  @override
  State<_QuickCreateCustomerSheet> createState() => _QuickCreateCustomerSheetState();
}

class _QuickCreateCustomerSheetState extends State<_QuickCreateCustomerSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _gstinCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  String _stateCode = '27';
  String _detectedStateName = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _gstinCtrl.addListener(_detectStateFromGstin);
  }

  void _detectStateFromGstin() {
    final gstin = _gstinCtrl.text.trim();
    if (gstin.length >= 2) {
      final prefix = gstin.substring(0, 2);
      if (_gstinStateCodeMap.containsKey(prefix)) {
        setState(() {
          _stateCode = prefix;
          _detectedStateName = _stateNames[prefix] ?? '';
        });
        return;
      }
    }
    // Clear if too short or invalid
    if (_detectedStateName.isNotEmpty) {
      setState(() => _detectedStateName = '');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _gstinCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final contact = ContactModel(
      id: '',
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      gstin: _gstinCtrl.text.trim().isEmpty ? null : _gstinCtrl.text.trim().toUpperCase(),
      contactType: widget.contactType,
      registrationType: _gstinCtrl.text.trim().isEmpty ? 'CONSUMER' : 'REGULAR',
      billingAddress: {'state_code': _stateCode},
      stateCode: _stateCode,
      isActive: true,
    );

    final provider = context.read<ContactProvider>();
    final success = await provider.addContact(contact);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        final nameToFind = _nameCtrl.text.trim().toLowerCase();
        final created = provider.contacts
            .where((c) => c.name.toLowerCase() == nameToFind)
            .lastOrNull;
        if (mounted) Navigator.pop(context, created);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'Failed to create ${widget.contactType == 'VENDOR' ? 'vendor' : 'customer'}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),

              // Title row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.brandNavy.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.person_add_rounded, color: AppColors.brandNavy, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(widget.contactType == 'VENDOR' ? 'New Vendor' : 'New Customer', style: AppTextStyles.h3)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Name
              TextFormField(
                controller: _nameCtrl,
                autofocus: widget.initialName == null,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  prefixIcon: Icon(Icons.person_outline, size: 18),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),

              // Phone + Email row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        prefixIcon: Icon(Icons.phone_outlined, size: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // GSTIN with auto state detection
              TextFormField(
                controller: _gstinCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 15,
                decoration: InputDecoration(
                  labelText: 'GSTIN (optional)',
                  prefixIcon: const Icon(Icons.receipt_long_outlined, size: 16),
                  counterText: '',
                  suffixIcon: _detectedStateName.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_on_rounded, size: 13, color: Color(0xFF2E7D32)),
                              const SizedBox(width: 3),
                              Text(
                                _detectedStateName,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF2E7D32),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),

              // State dropdown (auto-set from GSTIN but can override)
              DropdownButtonFormField<String>(
                value: _stateCode,
                decoration: const InputDecoration(
                  labelText: 'State *',
                  prefixIcon: Icon(Icons.map_outlined, size: 16),
                ),
                items: _stateNames.entries.map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text('${e.key} — ${e.value}', style: const TextStyle(fontSize: 13)),
                )).toList(),
                onChanged: (v) { if (v != null) setState(() => _stateCode = v); },
                validator: (v) => v == null ? 'State required' : null,
              ),
              const SizedBox(height: 20),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add_rounded, size: 16),
                            SizedBox(width: 6),
                            Text('Create & Select', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
