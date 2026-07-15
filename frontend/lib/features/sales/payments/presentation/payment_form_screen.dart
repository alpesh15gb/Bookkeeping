import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/features/masters/contacts/data/models/contact.dart';
import 'package:apexbooks/features/masters/contacts/presentation/contact_controller.dart';
import 'package:apexbooks/features/masters/shared/presentation/quick_create_dialogs.dart';
import '../models/payment_enums.dart';
import '../models/outstanding_invoice.dart';
import 'payment_providers.dart';
import 'payment_form_state.dart';

class PaymentFormScreen extends ConsumerStatefulWidget {
  const PaymentFormScreen({
    super.key,
    this.contactId,
    this.contactName,
    this.amount,
  });
  final String? contactId;
  final String? contactName;
  final double? amount;

  @override
  ConsumerState<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends ConsumerState<PaymentFormScreen> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _description = TextEditingController();
  final _date = TextEditingController();

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref
          .read(contactControllerProvider.notifier)
          .load(
            const ListQuery(limit: 100, extra: {'contact_type': 'CUSTOMER'}),
          );
      final notifier = ref.read(paymentFormProvider.notifier);
      _date.text = _today();
      notifier.setPaymentDate(_date.text);
      if (widget.amount != null) {
        _amount.text = widget.amount!.toStringAsFixed(2);
        notifier.setAmount(widget.amount!);
      }
      if (widget.contactId != null) {
        await notifier.selectCustomer(
          widget.contactId!,
          widget.contactName ?? 'Customer',
        );
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _description.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final payment = await ref.read(paymentFormProvider.notifier).create();
    if (payment != null && mounted) Navigator.pop(context, payment);
  }

  Future<void> _createCustomer() async {
    final created = await showQuickCreateParty(
      context,
      contactType: ContactType.customer,
    );
    if (created != null && mounted) {
      await ref
          .read(paymentFormProvider.notifier)
          .selectCustomer(created.id, created.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paymentFormProvider);
    final notifier = ref.read(paymentFormProvider.notifier);
    final fmt = ref.watch(numberFormatterProvider);
    final contactsState = ref.watch(contactControllerProvider);
    final contacts = contactsState is ListData<Contact>
        ? contactsState.paged.items
              .where(
                (c) =>
                    c.contactType == ContactType.customer ||
                    c.contactType == ContactType.both,
              )
              .toList()
        : <Contact>[];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyA, alt: true):
            notifier.autoAllocate,
        const SingleActivator(LogicalKeyboardKey.keyC, alt: true):
            _createCustomer,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('New Customer Receipt'),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: FilledButton.icon(
                  onPressed: state.saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save receipt  Ctrl+S'),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (state.error != null)
                MaterialBanner(
                  content: Text(state.error!),
                  leading: const Icon(Icons.error_outline),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('REVIEW')),
                  ],
                ),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 360,
                    child: Autocomplete<Contact>(
                      key: ValueKey(state.contactId),
                      initialValue: TextEditingValue(text: state.contactName),
                      displayStringForOption: (contact) => contact.name,
                      optionsBuilder: (value) {
                        final query = value.text.trim().toLowerCase();
                        if (query.isEmpty) return contacts.take(8);
                        final matches =
                            contacts
                                .where(
                                  (contact) =>
                                      contact.name.toLowerCase().contains(
                                        query,
                                      ) ||
                                      (contact.gstin ?? '')
                                          .toLowerCase()
                                          .contains(query) ||
                                      (contact.phone ?? '')
                                          .toLowerCase()
                                          .contains(query),
                                )
                                .toList()
                              ..sort((a, b) {
                                final aStarts = a.name.toLowerCase().startsWith(
                                  query,
                                );
                                final bStarts = b.name.toLowerCase().startsWith(
                                  query,
                                );
                                if (aStarts != bStarts) return aStarts ? -1 : 1;
                                return a.name.toLowerCase().compareTo(
                                  b.name.toLowerCase(),
                                );
                              });
                        return matches.take(12);
                      },
                      onSelected: (contact) =>
                          notifier.selectCustomer(contact.id, contact.name),
                      fieldViewBuilder: (context, controller, focusNode, _) =>
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  autofocus: widget.contactId == null,
                                  onChanged: (value) {
                                    if (state.contactId != null &&
                                        value.trim() != state.contactName) {
                                      notifier.clearCustomerSelection(value);
                                    }
                                  },
                                  decoration: const InputDecoration(
                                    labelText: 'Customer *',
                                    hintText: 'Type name, phone or GSTIN',
                                    prefixIcon: Icon(
                                      Icons.person_search_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'New customer (Alt+C)',
                                onPressed: _createCustomer,
                                icon: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                ),
                              ),
                            ],
                          ),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: TextFormField(
                      controller: _date,
                      decoration: const InputDecoration(
                        labelText: 'Receipt date *',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      onChanged: notifier.setPaymentDate,
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _amount,
                      autofocus: widget.contactId != null,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Amount received *',
                        prefixIcon: Icon(Icons.currency_rupee),
                      ),
                      onChanged: (v) =>
                          notifier.setAmount(double.tryParse(v) ?? 0),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: state.paymentMode,
                      decoration: const InputDecoration(labelText: 'Mode *'),
                      items: PaymentMode.values
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.value,
                              child: Text(m.value.replaceAll('_', ' ')),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) notifier.setPaymentMode(v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: TextField(
                      controller: _reference,
                      decoration: const InputDecoration(
                        labelText: 'Bank / cheque reference',
                      ),
                      onChanged: notifier.setReferenceNumber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    'Invoice allocation',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: notifier.autoAllocate,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Oldest first  Alt+A'),
                  ),
                ],
              ),
              if (state.loadingInvoices) const LinearProgressIndicator(),
              if (!state.loadingInvoices &&
                  state.contactId != null &&
                  state.availableInvoices.isEmpty)
                const ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('No outstanding invoices'),
                  subtitle: Text(
                    'The full receipt will be recorded as customer advance credit.',
                  ),
                ),
              ...state.availableInvoices.map(
                (invoice) => _AllocationRow(
                  invoice: invoice,
                  state: state,
                  formatter: fmt,
                  onChanged: (v) => notifier.setInvoiceAllocation(invoice, v),
                ),
              ),
              if (state.unallocated > 0) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: state.advanceSupplyType,
                  decoration: const InputDecoration(
                    labelText: 'Advance is for',
                    helperText:
                        'Service advances require GST and cannot be recorded as an untaxed credit.',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'GOODS', child: Text('Goods')),
                    DropdownMenuItem(
                      value: 'SERVICES',
                      child: Text('Services (taxable at receipt)'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) notifier.setAdvanceSupplyType(value);
                  },
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _description,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Narration / internal note',
                ),
                onChanged: notifier.setDescription,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 30,
                    runSpacing: 8,
                    children: [
                      Text('Received: ${fmt.currency(state.amount)}'),
                      Text('Allocated: ${fmt.currency(state.allocatedTotal)}'),
                      Text(
                        'Advance credit: ${fmt.currency(state.unallocated)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
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

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.invoice,
    required this.state,
    required this.formatter,
    required this.onChanged,
  });
  final OutstandingInvoice invoice;
  final PaymentFormState state;
  final NumberFormatter formatter;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final matches = state.allocations.where((a) => a.invoiceId == invoice.id);
    final value = matches.isEmpty ? 0.0 : matches.first.amount;
    return ListTile(
      dense: true,
      leading: Icon(
        invoice.isOverdue ? Icons.warning_amber : Icons.receipt_long_outlined,
      ),
      title: Text(invoice.invoiceNumber),
      subtitle: Text(
        invoice.isOverdue
            ? '${invoice.daysOverdue} days overdue · due ${invoice.dueDate}'
            : 'Due ${invoice.dueDate}',
      ),
      trailing: SizedBox(
        width: 310,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${formatter.currency(invoice.outstanding)} due',
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: TextFormField(
                key: ValueKey('${invoice.id}-$value'),
                initialValue: value > 0 ? value.toStringAsFixed(2) : '',
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Allocate',
                  isDense: true,
                ),
                onChanged: (v) => onChanged(double.tryParse(v) ?? 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
