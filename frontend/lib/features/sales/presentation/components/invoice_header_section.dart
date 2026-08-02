/// Invoice Header Section — Customer, dates, references.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/features/masters/contacts/presentation/contact_controller.dart';
import 'package:apexbooks/features/masters/contacts/data/models/contact.dart';
import 'package:apexbooks/features/masters/shared/presentation/quick_create_dialogs.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/permissions/permissions.dart';
import '../invoice_form_notifier.dart';
import '../invoice_form_state.dart';

class InvoiceHeaderSection extends ConsumerWidget {
  const InvoiceHeaderSection({
    super.key,
    required this.state,
    required this.notifier,
    required this.fmt,
  });

  final InvoiceFormState state;
  final InvoiceFormNotifier notifier;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final textTheme = Theme.of(context).textTheme;

    return ApexCard(
      elevation: CardElevation.low,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Text(
            'Invoice Details',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),

          // Row 1: Invoice Number & Dates
          Row(
            children: [
              // Invoice Number
              Expanded(
                child: ApexTextField(
                  controller: null,
                  label: 'Invoice Number',
                  initialValue: state.invoiceNumber,
                  hint: 'Auto-generated',
                  readOnly: state.originalId != null,
                  enabled: state.originalId == null,
                  onChanged: (v) {},
                ),
              ),
              const SizedBox(width: 16),
              // Issue Date
              Expanded(
                child: ApexDateField(
                  label: 'Issue Date',
                  value: state.issueDate,
                  onChanged: (d) {
                    if (d != null) notifier.setIssueDate(d);
                  },
                  hint: 'DD/MM/YYYY',
                ),
              ),
              const SizedBox(width: 16),
              // Due Date
              Expanded(
                child: ApexDateField(
                  label: 'Due Date',
                  value: state.dueDate,
                  onChanged: (d) {
                    if (d != null) notifier.setDueDate(d);
                  },
                  hint: 'DD/MM/YYYY',
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Row 2: Customer Picker & POS State
          Row(
            children: [
              // Customer
              Expanded(
                flex: 3,
                child: _CustomerPicker(state: state, notifier: notifier),
              ),
              const SizedBox(width: 16),
              // POS State
              Expanded(
                child: ApexDropdownField<String>(
                  label: 'Place of Supply',
                  value: state.posStateCode.isEmpty ? null : state.posStateCode,
                  items: _indianStates
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.code,
                          child: Text('${s.code} - ${s.name}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) notifier.setPosStateCode(v);
                  },
                  hint: 'Select state',
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Row 3: Reference Number & GST Options
          Row(
            children: [
              // Reference Number
              Expanded(
                child: ApexTextField(
                  controller: null,
                  label: 'Reference Number',
                  initialValue: state.referenceNumber ?? '',
                  hint: 'PO #, Contract #, etc.',
                  onChanged: notifier.setReferenceNumber,
                ),
              ),
              const SizedBox(width: 16),
              // GST Inclusive Toggle
              Expanded(
                child: _GstOptions(
                  isGstInclusive: state.isGstInclusive,
                  isRcm: state.isRcm,
                  supplyType: state.supplyType,
                  onGstInclusiveChanged: notifier.setIsGstInclusive,
                  onRcmChanged: notifier.setIsRcm,
                  onSupplyTypeChanged: notifier.setSupplyType,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Row 4: Shipping Charges & TDS/TCS
          Row(
            children: [
              // Shipping Charges
              Expanded(
                child: ApexMonetaryField(
                  label: 'Shipping Charges',
                  controller: TextEditingController(
                    text: state.shippingCharges > 0
                        ? fmt.quantity(state.shippingCharges)
                        : '',
                  ),
                  onChanged: (v) => notifier.setShippingCharges(
                    double.tryParse(v.replaceAll(',', '')) ?? 0,
                  ),
                  hint: '₹0.00',
                ),
              ),
              const SizedBox(width: 16),
              // TDS Rate
              Expanded(
                child: ApexDropdownField<double>(
                  label: 'TDS Rate (%)',
                  value: state.tdsRate,
                  items: [0, 1, 2, 5, 10]
                      .map(
                        (r) => DropdownMenuItem<double>(
                          value: r.toDouble(),
                          child: Text('$r%'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => v != null ? notifier.setTdsRate(v) : null,
                ),
              ),
              const SizedBox(width: 16),
              // TCS Rate
              Expanded(
                child: ApexDropdownField<double>(
                  label: 'TCS Rate (%)',
                  value: state.tcsRate,
                  items: [0.0, 0.1, 0.5, 1.0]
                      .map(
                        (r) => DropdownMenuItem<double>(
                          value: r,
                          child: Text('$r%'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => v != null ? notifier.setTcsRate(v) : null,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _CustomerPicker extends ConsumerWidget {
  const _CustomerPicker({required this.state, required this.notifier});

  final InvoiceFormState state;
  final InvoiceFormNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    ref.watch(contactControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer',
          style: textTheme.labelMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _showCustomerPicker(context, ref),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.border, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        color: colors.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          state.contactName.isEmpty
                              ? 'Select customer'
                              : state.contactName,
                          style: textTheme.bodyMedium?.copyWith(
                            color: state.contactName.isEmpty
                                ? colors.textMuted
                                : colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (state.contactId != null)
                        IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: colors.textMuted,
                            size: 18,
                          ),
                          onPressed: () => notifier.clearContact(),
                          tooltip: 'Clear customer',
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Quick create customer
            PermissionGate(
              permission: Permissions.contactCreate,
              child: ApexIconButton(
                icon: Icons.add,
                onPressed: () => _quickCreateCustomer(context, ref),
                tooltip: 'Create new customer',
                size: 44,
              ),
            ),
          ],
        ),
        if (state.contactId != null &&
            (state.billingAddress != null ||
                state.contactGstNumber != null)) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              if (state.contactGstNumber != null)
                _InfoChip(
                  label: 'GSTIN: ${state.contactGstNumber}',
                  icon: Icons.receipt_long,
                ),
              if (state.billingAddress != null)
                _InfoChip(
                  label: 'Billing: ${state.billingAddress!.split('\n').first}',
                  icon: Icons.location_on_outlined,
                ),
            ],
          ),
        ],
      ],
    );
  }

  void _showCustomerPicker(BuildContext context, WidgetRef ref) {
    final contactState = ref.read(contactControllerProvider);
    final all = switch (contactState) {
      ListData<Contact>(:final paged) => paged.items,
      _ => const <Contact>[],
    };
    final contacts = all
        .where(
          (c) =>
              c.contactType == ContactType.customer ||
              c.contactType == ContactType.both,
        )
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: apexColors(context).surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: apexColors(context).border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Select Customer',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: contacts.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: apexColors(context).border),
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          contact.name.isNotEmpty
                              ? contact.name[0].toUpperCase()
                              : '?',
                        ),
                      ),
                      title: Text(contact.name),
                      subtitle: Text(
                        '${contact.gstin ?? 'No GSTIN'} • ${contact.billingAddress?.city ?? ''}',
                      ),
                      onTap: () {
                        notifier.setContact(contact);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _quickCreateCustomer(BuildContext context, WidgetRef ref) async {
    final result = await showQuickCreateParty(
      context,
      contactType: ContactType.customer,
    );
    if (result != null && context.mounted) {
      ref.invalidate(contactControllerProvider);
      // Auto-select the new contact
      notifier.setContact(result);
    }
  }
}

class _GstOptions extends StatelessWidget {
  const _GstOptions({
    required this.isGstInclusive,
    required this.isRcm,
    required this.supplyType,
    required this.onGstInclusiveChanged,
    required this.onRcmChanged,
    required this.onSupplyTypeChanged,
  });

  final bool isGstInclusive;
  final bool isRcm;
  final String supplyType;
  final ValueChanged<bool> onGstInclusiveChanged;
  final ValueChanged<bool> onRcmChanged;
  final ValueChanged<String> onSupplyTypeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GST Options',
          style: textTheme.labelMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            // GST Inclusive
            InkWell(
              onTap: () => onGstInclusiveChanged(!isGstInclusive),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isGstInclusive
                      ? colors.primaryContainer
                      : colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isGstInclusive ? colors.primary : colors.border,
                    width: isGstInclusive ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isGstInclusive
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                      color: isGstInclusive ? colors.primary : colors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'GST Inclusive',
                      style: textTheme.labelMedium?.copyWith(
                        color: isGstInclusive
                            ? colors.primary
                            : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // RCM
            InkWell(
              onTap: () => onRcmChanged(!isRcm),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isRcm ? colors.warningContainer : colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isRcm ? colors.warning : colors.border,
                    width: isRcm ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isRcm ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18,
                      color: isRcm ? colors.warning : colors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'RCM',
                      style: textTheme.labelMedium?.copyWith(
                        color: isRcm ? colors.warning : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Supply Type
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: supplyType,
                  items: ['DOMESTIC', 'EXPORT', 'SEZ']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => v != null ? onSupplyTypeChanged(v) : null,
                  style: textTheme.labelMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// Indian state/UT GST codes (2-digit numeric) for POS
class _StateOption {
  const _StateOption(this.code, this.name);
  final String code;
  final String name;
}

const List<_StateOption> _indianStates = [
  _StateOption('01', 'Jammu and Kashmir'),
  _StateOption('02', 'Himachal Pradesh'),
  _StateOption('03', 'Punjab'),
  _StateOption('04', 'Chandigarh'),
  _StateOption('05', 'Uttarakhand'),
  _StateOption('06', 'Haryana'),
  _StateOption('07', 'Delhi'),
  _StateOption('08', 'Rajasthan'),
  _StateOption('09', 'Uttar Pradesh'),
  _StateOption('10', 'Bihar'),
  _StateOption('11', 'Sikkim'),
  _StateOption('12', 'Arunachal Pradesh'),
  _StateOption('13', 'Nagaland'),
  _StateOption('14', 'Manipur'),
  _StateOption('15', 'Mizoram'),
  _StateOption('16', 'Tripura'),
  _StateOption('17', 'Meghalaya'),
  _StateOption('18', 'Assam'),
  _StateOption('19', 'West Bengal'),
  _StateOption('20', 'Jharkhand'),
  _StateOption('21', 'Odisha'),
  _StateOption('22', 'Chhattisgarh'),
  _StateOption('23', 'Madhya Pradesh'),
  _StateOption('24', 'Gujarat'),
  _StateOption('25', 'Goa'),
  _StateOption('26', 'Dadra and Nagar Haveli and Daman and Diu'),
  _StateOption('27', 'Maharashtra'),
  _StateOption('28', 'Karnataka'),
  _StateOption('29', 'Telangana'),
  _StateOption('30', 'Andhra Pradesh'),
  _StateOption('31', 'Lakshadweep'),
  _StateOption('32', 'Kerala'),
  _StateOption('33', 'Tamil Nadu'),
  _StateOption('34', 'Puducherry'),
  _StateOption('35', 'Andaman and Nicobar Islands'),
  _StateOption('37', 'Ladakh'),
];
