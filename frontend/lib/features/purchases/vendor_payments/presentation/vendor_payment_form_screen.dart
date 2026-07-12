import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/features/masters/contacts/presentation/contact_controller.dart';
import 'package:apexbooks/features/masters/contacts/data/models/contact.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import '../models/outstanding_bill.dart';
import '../models/vendor_payment_enums.dart';
import 'vendor_payment_form_notifier.dart';
import 'vendor_payment_form_state.dart';

class VendorPaymentFormScreen extends ConsumerStatefulWidget {
  const VendorPaymentFormScreen({super.key});
  @override
  ConsumerState<VendorPaymentFormScreen> createState() =>
      _VendorPaymentFormScreenState();
}

class _VendorPaymentFormScreenState
    extends ConsumerState<VendorPaymentFormScreen> {
  final _vendorFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(contactControllerProvider.notifier)
          .load(const ListQuery(limit: 100));
      ref
          .read(vendorPaymentFormProvider.notifier)
          .setPaymentDate(_fmtDate(DateTime.now()));
      _vendorFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _vendorFocus.dispose();
    super.dispose();
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  DateTime? _parseDate(String s) => DateTime.tryParse(s);

  Future<void> _save() async {
    final notifier = ref.read(vendorPaymentFormProvider.notifier);
    if (ref.read(vendorPaymentFormProvider).saving) return;
    if (await notifier.create() != null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vendorPaymentFormProvider);
    final notifier = ref.read(vendorPaymentFormProvider.notifier);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final contactsState = ref.watch(contactControllerProvider);
    final contacts = contactsState is ListData<Contact>
        ? contactsState.paged.items
        : <Contact>[];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colors.surfaceMuted,
          appBar: AppBar(
            backgroundColor: colors.surfaceRaised,
            elevation: 0,
            titleSpacing: 20,
            title: Text(
              'New Vendor Payment',
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
                  onPressed: state.saving ? null : _save,
                  icon: state.saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: LoadingSpinner(size: 16),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save payment'),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              if (state.error != null)
                Container(
                  width: double.infinity,
                  color: colors.danger.withValues(alpha: 0.1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: colors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.error!,
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
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _headerCard(state, notifier, colors, contacts),
                        const SizedBox(height: 16),
                        if (state.loadingBills)
                          const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: LoadingSpinner(size: 30)),
                          )
                        else if (state.hasVendor)
                          _allocationsCard(state, notifier, colors, fmt)
                        else
                          _Card(
                            colors: colors,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: colors.textMuted,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Select a vendor to load their outstanding bills.',
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              _summaryBar(state, colors, fmt),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCard(
    VendorPaymentFormState state,
    VendorPaymentFormNotifier notifier,
    ApexColors colors,
    List<Contact> contacts,
  ) {
    return _Card(
      colors: colors,
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 720;
              final vendor = _labeled(
                'Vendor',
                _VendorField(
                  focusNode: _vendorFocus,
                  contacts: contacts,
                  selectedName: state.contactName,
                  colors: colors,
                  onSelected: (ct) => notifier.selectVendor(ct.id, ct.name),
                ),
                colors,
                required: true,
              );
              final payNo = _labeled(
                'Payment No.',
                TextField(
                  decoration: _dec(
                    colors,
                    hint: 'e.g. VP-0001',
                    icon: Icons.tag_rounded,
                  ),
                  onChanged: notifier.setPaymentNumber,
                ),
                colors,
                required: true,
              );
              final date = _labeled(
                'Date',
                _DateField(
                  value: state.paymentDate,
                  colors: colors,
                  onPick: (d) => notifier.setPaymentDate(_fmtDate(d)),
                  parse: _parseDate,
                ),
                colors,
              );
              if (narrow)
                return Column(
                  children: [
                    vendor,
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: payNo),
                        const SizedBox(width: 12),
                        Expanded(child: date),
                      ],
                    ),
                  ],
                );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: vendor),
                  const SizedBox(width: 16),
                  Expanded(child: payNo),
                  const SizedBox(width: 16),
                  Expanded(child: date),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _labeled(
                  'Amount',
                  TextField(
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: _dec(
                      colors,
                      hint: '0.00',
                      icon: Icons.payments_rounded,
                    ),
                    onChanged: (v) =>
                        notifier.setAmount(double.tryParse(v) ?? 0),
                  ),
                  colors,
                  required: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _labeled(
                  'Mode',
                  DropdownButtonFormField<PaymentMode>(
                    initialValue: state.paymentMode,
                    decoration: _dec(
                      colors,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    items: PaymentMode.values
                        .map(
                          (m) =>
                              DropdownMenuItem(value: m, child: Text(m.value)),
                        )
                        .toList(),
                    onChanged: (m) {
                      if (m != null) notifier.setPaymentMode(m);
                    },
                  ),
                  colors,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _labeled(
                  'Reference',
                  TextField(
                    decoration: _dec(
                      colors,
                      hint: 'Txn / cheque no.',
                      icon: Icons.receipt_long_outlined,
                    ),
                    onChanged: notifier.setReference,
                  ),
                  colors,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _allocationsCard(
    VendorPaymentFormState state,
    VendorPaymentFormNotifier notifier,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    if (state.bills.isEmpty) {
      return _Card(
        colors: colors,
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 18, color: colors.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'This vendor has no outstanding bills.',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    final allocTable = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: colors.surfaceMuted,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(flex: 34, child: Text('BILL', style: _th(colors))),
              Expanded(
                flex: 18,
                child: Text(
                  'DUE',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 22,
                child: Text(
                  'OUTSTANDING',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 26,
                child: Text(
                  'ALLOCATE',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
            ],
          ),
        ),
        ...state.bills.map(
          (b) => _AllocRow(
            key: ValueKey('alloc_${b.id}'),
            bill: b,
            allocated: state.allocations[b.id] ?? 0,
            colors: colors,
            fmt: fmt,
            onChanged: (v) => notifier.setAllocation(b.id, v),
          ),
        ),
      ],
    );
    return _Card(
      colors: colors,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
            child: Row(
              children: [
                Text(
                  'Allocate to bills',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: notifier.autoAllocate,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: const Text('Auto-allocate'),
                ),
              ],
            ),
          ),
          if (ResponsiveLayout.isMobile(context))
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: allocTable,
            )
          else
            allocTable,
        ],
      ),
    );
  }

  Widget _summaryBar(
    VendorPaymentFormState state,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final over = state.totalAllocated > state.amount + 0.01;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(top: BorderSide(color: colors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 28,
        vertical: 14,
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _tot('Payment', fmt.currency(state.amount), colors),
                    _tot(
                      'Allocated',
                      fmt.currency(state.totalAllocated),
                      colors,
                      tone: over ? colors.danger : null,
                    ),
                    _tot(
                      'Unallocated',
                      fmt.currency(state.unallocated),
                      colors,
                      emphasize: true,
                    ),
                    FilledButton.icon(
                      onPressed: state.saving ? null : _save,
                      icon: state.saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: LoadingSpinner(size: 16),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Save'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                const Spacer(),
                _tot('Payment', fmt.currency(state.amount), colors),
                _sep(colors),
                _tot(
                  'Allocated',
                  fmt.currency(state.totalAllocated),
                  colors,
                  tone: over ? colors.danger : null,
                ),
                _sep(colors),
                _tot(
                  'Unallocated',
                  fmt.currency(state.unallocated),
                  colors,
                  emphasize: true,
                ),
                const SizedBox(width: 24),
                FilledButton.icon(
                  onPressed: state.saving ? null : _save,
                  icon: state.saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: LoadingSpinner(size: 16),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save  (Ctrl+S)'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _tot(
    String label,
    String value,
    ApexColors colors, {
    bool emphasize = false,
    Color? tone,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          color: colors.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          fontSize: emphasize ? 18 : 14,
          fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
          color: tone ?? (emphasize ? colors.primary : colors.textPrimary),
        ),
      ),
    ],
  );

  Widget _sep(ApexColors colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Container(width: 1, height: 30, color: colors.border),
  );

  Widget _labeled(
    String label,
    Widget field,
    ApexColors colors, {
    bool required = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
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

  TextStyle _th(ApexColors colors) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: colors.textMuted,
  );
}

class _Card extends StatelessWidget {
  const _Card({
    required this.colors,
    required this.child,
    this.padding,
  });
  final ApexColors colors;
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) =>
      ApexCard(padding: padding ?? const EdgeInsets.all(20), child: child);
}

class _VendorField extends StatelessWidget {
  const _VendorField({
    required this.focusNode,
    required this.contacts,
    required this.selectedName,
    required this.colors,
    required this.onSelected,
  });
  final FocusNode focusNode;
  final List<Contact> contacts;
  final String selectedName;
  final ApexColors colors;
  final void Function(Contact) onSelected;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Contact>(
      displayStringForOption: (c) => c.name,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return contacts.take(8);
        return contacts
            .where(
              (c) =>
                  c.name.toLowerCase().contains(q) ||
                  (c.gstin ?? '').toLowerCase().contains(q),
            )
            .take(12);
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, ctrl, fn, onSubmit) {
        if (selectedName.isNotEmpty && ctrl.text.isEmpty)
          ctrl.text = selectedName;
        return TextField(
          controller: ctrl,
          focusNode: focusNode,
          decoration: _dec(
            colors,
            hint: 'Search vendor or GSTIN…',
            icon: Icons.storefront_outlined,
          ),
        );
      },
      optionsViewBuilder: (context, onSel, options) {
        final list = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(ApexRadius.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300, maxWidth: 420),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: BorderRadius.circular(ApexRadius.md),
                  border: Border.all(color: colors.border),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final o = list[i];
                    return InkWell(
                      onTap: () => onSel(o),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              o.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            if ((o.gstin ?? '').isNotEmpty)
                              Text(
                                o.gstin!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.colors,
    required this.onPick,
    required this.parse,
  });
  final String value;
  final ApexColors colors;
  final void Function(DateTime) onPick;
  final DateTime? Function(String) parse;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(ApexRadius.sm),
      onTap: () async {
        final init = parse(value) ?? DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: init,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: _dec(colors, icon: Icons.calendar_today_rounded),
        child: Text(
          value.isEmpty ? 'Select…' : value,
          style: TextStyle(
            color: value.isEmpty ? colors.textMuted : colors.textPrimary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _AllocRow extends StatefulWidget {
  const _AllocRow({
    super.key,
    required this.bill,
    required this.allocated,
    required this.colors,
    required this.fmt,
    required this.onChanged,
  });
  final OutstandingBill bill;
  final double allocated;
  final ApexColors colors;
  final NumberFormatter fmt;
  final void Function(double) onChanged;
  @override
  State<_AllocRow> createState() => _AllocRowState();
}

class _AllocRowState extends State<_AllocRow> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.allocated > 0 ? _num(widget.allocated) : '',
    );
  }

  @override
  void didUpdateWidget(_AllocRow old) {
    super.didUpdateWidget(old);
    if (widget.allocated != old.allocated &&
        (double.tryParse(_ctrl.text) ?? 0) != widget.allocated) {
      _ctrl.text = widget.allocated > 0 ? _num(widget.allocated) : '';
    }
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final b = widget.bill;
    final over = widget.allocated > b.outstanding + 0.01;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 34,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.billNumber.isEmpty ? 'Bill' : b.billNumber,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                if (b.isOverdue)
                  Text(
                    '${b.daysOverdue}d overdue',
                    style: TextStyle(fontSize: 11, color: c.danger),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 18,
            child: Text(
              b.dueDate.isEmpty ? '—' : b.dueDate,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12.5, color: c.textSecondary),
            ),
          ),
          Expanded(
            flex: 22,
            child: Text(
              widget.fmt.currency(b.outstanding),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 26,
            child: TextField(
              controller: _ctrl,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: TextStyle(
                fontSize: 13,
                color: over ? c.danger : c.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: '0.00',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ApexRadius.sm),
                ),
                enabledBorder: over
                    ? OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ApexRadius.sm),
                        borderSide: BorderSide(color: c.danger),
                      )
                    : null,
              ),
              onChanged: (v) => widget.onChanged(double.tryParse(v) ?? 0),
            ),
          ),
        ],
      ),
    );
  }
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
    );
