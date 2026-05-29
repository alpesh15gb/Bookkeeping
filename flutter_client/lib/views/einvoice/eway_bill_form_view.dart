import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/eway_bill_provider.dart';
import 'package:flutter_client/providers/invoice_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class EwayBillFormView extends StatefulWidget {
  const EwayBillFormView({super.key});

  @override
  State<EwayBillFormView> createState() => _EwayBillFormViewState();
}

class _EwayBillFormViewState extends State<EwayBillFormView> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  String? _invoiceId;
  late final TextEditingController _vehicleNumberCtrl;
  late final TextEditingController _transporterNameCtrl;
  late final TextEditingController _transporterIdCtrl;
  late final TextEditingController _fromPlaceCtrl;
  late final TextEditingController _toPlaceCtrl;
  late final TextEditingController _distanceCtrl;

  List<dynamic> _invoices = [];

  @override
  void initState() {
    super.initState();
    _vehicleNumberCtrl = TextEditingController();
    _transporterNameCtrl = TextEditingController();
    _transporterIdCtrl = TextEditingController();
    _fromPlaceCtrl = TextEditingController();
    _toPlaceCtrl = TextEditingController();
    _distanceCtrl = TextEditingController();

    Future.microtask(() async {
      final provider = context.read<InvoiceProvider>();
      await provider.fetchInvoices(status: 'SENT');
      if (mounted) setState(() => _invoices = provider.invoices);
    });
  }

  @override
  void dispose() {
    _vehicleNumberCtrl.dispose();
    _transporterNameCtrl.dispose();
    _transporterIdCtrl.dispose();
    _fromPlaceCtrl.dispose();
    _toPlaceCtrl.dispose();
    _distanceCtrl.dispose();
    super.dispose();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_invoiceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an invoice'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isSaving = true);

    final payload = {
      'invoice_id': _invoiceId,
      'vehicle_number': _vehicleNumberCtrl.text.trim(),
      'transporter_name': _transporterNameCtrl.text.trim().isEmpty ? null : _transporterNameCtrl.text.trim(),
      'transporter_id': _transporterIdCtrl.text.trim().isEmpty ? null : _transporterIdCtrl.text.trim(),
      'from_place': _fromPlaceCtrl.text.trim(),
      'to_place': _toPlaceCtrl.text.trim(),
      'distance_km': int.tryParse(_distanceCtrl.text) ?? 0,
    };

    final provider = context.read<EwayBillProvider>();
    final success = await provider.generateEwayBill(payload);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('E-Way Bill generated'), backgroundColor: AppColors.success),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Generation failed'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Generate E-Way Bill'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('GENERATE'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
          children: [
            _FormCard(
              title: 'INVOICE',
              child: DropdownButtonFormField<String>(
                value: _invoiceId,
                decoration: const InputDecoration(labelText: 'Invoice *', prefixIcon: Icon(Icons.description, size: 18)),
                items: _invoices.map((inv) => DropdownMenuItem<String>(
                  value: inv.id,
                  child: Text('${inv.invoiceNumber} - ₹${(inv.total as num).toStringAsFixed(2)}'),
                )).toList(),
                onChanged: (v) => setState(() => _invoiceId = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
            ),
            const SizedBox(height: 16),
            _FormCard(
              title: 'TRANSPORT DETAILS',
              child: Column(
                children: [
                  TextFormField(
                    controller: _vehicleNumberCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Vehicle Number *', prefixIcon: Icon(Icons.local_shipping, size: 18)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _transporterNameCtrl,
                    decoration: const InputDecoration(labelText: 'Transporter Name', prefixIcon: Icon(Icons.business, size: 18)),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _transporterIdCtrl,
                    decoration: const InputDecoration(labelText: 'Transporter GSTIN / ID', prefixIcon: Icon(Icons.badge, size: 18)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _FormCard(
              title: 'ROUTE',
              child: Column(
                children: [
                  TextFormField(
                    controller: _fromPlaceCtrl,
                    decoration: const InputDecoration(labelText: 'From *', prefixIcon: Icon(Icons.trip_origin, size: 18)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _toPlaceCtrl,
                    decoration: const InputDecoration(labelText: 'To *', prefixIcon: Icon(Icons.location_on, size: 18)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _distanceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Distance (km)', prefixIcon: Icon(Icons.route, size: 18)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _FormCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(color: AppColors.bgSurface, borderRadius: AppRadius.card, border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.labelSmall),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
