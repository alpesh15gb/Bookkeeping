import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/dialogs/dialog_service.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/features/masters/contacts/presentation/contact_controller.dart';
import 'package:apexbooks/features/masters/contacts/data/models/contact.dart';
import 'package:apexbooks/features/masters/contacts/presentation/contact_search.dart';
import 'package:apexbooks/features/masters/products/presentation/product_controller.dart';
import 'package:apexbooks/features/masters/products/data/models/product.dart';
import 'package:apexbooks/features/masters/products/presentation/barcode_product_field.dart';
import 'package:apexbooks/features/masters/shared/presentation/quick_create_dialogs.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/permissions/permissions_constants.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import '../models/bill_line.dart';
import 'bill_form_notifier.dart';
import 'bill_form_state.dart';
import 'package:apexbooks/features/auth/presentation/auth_controller.dart';
import 'package:apexbooks/features/settings/presentation/settings_providers.dart';
import 'package:apexbooks/core/result/result.dart';

class BillFormScreen extends ConsumerStatefulWidget {
  const BillFormScreen({super.key});
  @override
  ConsumerState<BillFormScreen> createState() => _BillFormScreenState();
}

class _BillFormScreenState extends ConsumerState<BillFormScreen> {
  final _vendorFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(contactControllerProvider.notifier)
          .load(const ListQuery(limit: 100, extra: {'contact_type': 'VENDOR'}));
      ref
          .read(productControllerProvider.notifier)
          .load(const ListQuery(limit: 100));
      final now = DateTime.now();
      final n = ref.read(billFormProvider.notifier);
      n.setIssueDate(_fmtDate(now));
      n.setDueDate(_fmtDate(now.add(const Duration(days: 15))));
      ref.read(settingsRepositoryProvider).getTenantSettings().then((result) {
        final settings = result.dataOrNull;
        if (settings != null && mounted) {
          n.setOriginStateCode(settings.originStateCode ?? '');
          final terms = settings.extraSettings['terms']?.toString() ?? '';
          if (terms.isNotEmpty &&
              ref.read(billFormProvider).termsAndConditions == null) {
            n.setTerms(terms);
          }
        }
      });
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

  bool get _hasUnsavedChanges {
    final s = ref.read(billFormProvider);
    return s.contactId != null ||
        s.billNumber.isNotEmpty ||
        s.lines.any((l) => l.productId.isNotEmpty);
  }

  Future<void> _save() async {
    final notifier = ref.read(billFormProvider.notifier);
    if (ref.read(billFormProvider).saving) return;
    if (await notifier.create() != null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(billFormProvider);
    final notifier = ref.read(billFormProvider.notifier);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final gstEnabled = ref.watch(gstEnabledProvider);

    final contactsState = ref.watch(contactControllerProvider);
    final allContacts = contactsState is ListData<Contact>
        ? contactsState.paged.items
        : <Contact>[];
    final contacts = allContacts
        .where(
          (c) =>
              c.contactType == ContactType.vendor ||
              c.contactType == ContactType.both,
        )
        .toList();
    final productsState = ref.watch(productControllerProvider);
    final products = productsState is ListData<Product>
        ? productsState.paged.items
        : <Product>[];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyN, alt: true):
            notifier.addLine,
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (_hasUnsavedChanges) {
              final result = await const DialogService().unsavedChanges(
                context,
              );
              if (result == DialogResult.discard && context.mounted) {
                Navigator.of(context).pop();
              }
            } else {
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
                'New Vendor Bill',
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
                    label: const Text('Save Bill'),
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
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          _headerCard(state, notifier, colors, contacts),
                          const SizedBox(height: 16),
                          _linesCard(
                            state,
                            notifier,
                            colors,
                            fmt,
                            products,
                            gstEnabled,
                          ),
                          const SizedBox(height: 16),
                          _optionsCard(state, notifier, colors, gstEnabled),
                        ],
                      ),
                    ),
                  ),
                ),
                _totalsBar(state, colors, fmt, gstEnabled),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCard(
    BillFormState state,
    BillFormNotifier notifier,
    ApexColors colors,
    List<Contact> contacts,
  ) {
    return _Card(
      colors: colors,
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 720;
          final vendor = _labeled(
            'Vendor',
            _VendorField(
              focusNode: _vendorFocus,
              contacts: contacts,
              selectedName: state.contactName,
              colors: colors,
              onSelected: (ct) {
                notifier.setContact(ct.id, ct.name);
                if (ct.stateCode != null && ct.stateCode!.isNotEmpty) {
                  notifier.setPosStateCode(ct.stateCode!);
                }
              },
            ),
            colors,
            required: true,
          );
          final billNo = _labeled(
            'Bill Number',
            TextField(
              decoration: _dec(
                colors,
                hint: 'e.g. BILL-0001',
                icon: Icons.tag_rounded,
              ),
              onChanged: notifier.setBillNumber,
            ),
            colors,
            required: true,
          );
          final issue = _labeled(
            'Bill date',
            _DateField(
              value: state.issueDate,
              colors: colors,
              onPick: (d) => notifier.setIssueDate(_fmtDate(d)),
              parse: _parseDate,
            ),
            colors,
          );
          final due = _labeled(
            'Due date',
            _DateField(
              value: state.dueDate,
              colors: colors,
              onPick: (d) => notifier.setDueDate(_fmtDate(d)),
              parse: _parseDate,
            ),
            colors,
          );
          final refNo = _labeled(
            'Reference number',
            TextField(
              decoration: _dec(
                colors,
                hint: 'e.g. PO-001',
                icon: Icons.description_outlined,
              ),
              onChanged: notifier.setReferenceNumber,
            ),
            colors,
          );
          if (narrow) {
            return Column(
              children: [
                vendor,
                const SizedBox(height: 12),
                billNo,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: issue),
                    const SizedBox(width: 12),
                    Expanded(child: due),
                  ],
                ),
                const SizedBox(height: 12),
                refNo,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: vendor),
                  const SizedBox(width: 16),
                  Expanded(child: billNo),
                  const SizedBox(width: 16),
                  Expanded(child: issue),
                  const SizedBox(width: 16),
                  Expanded(child: due),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(width: 420, child: refNo),
            ],
          );
        },
      ),
    );
  }

  Widget _linesCard(
    BillFormState state,
    BillFormNotifier notifier,
    ApexColors colors,
    NumberFormatter fmt,
    List<Product> products,
    bool gstEnabled,
  ) {
    final lineTable = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ApexRadius.lg),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const _HCell('ITEM', flex: 34),
              const _HCell('HSN', flex: 12),
              const _HCell('QTY', flex: 10, right: true),
              const _HCell('RATE', flex: 14, right: true),
              const _HCell('DISC%', flex: 10, right: true),
              if (gstEnabled) const _HCell('GST%', flex: 10, right: true),
              const _HCell('AMOUNT', flex: 14, right: true),
              const SizedBox(width: 36),
            ],
          ),
        ),
        ...state.lines.asMap().entries.map(
          (e) => _BillLineRow(
            key: ValueKey('bill_line_${e.key}'),
            line: e.value,
            products: products,
            colors: colors,
            fmt: fmt,
            gstEnabled: gstEnabled,
            canRemove: state.lines.length > 1,
            onChanged: (l) => notifier.updateLine(e.key, l),
            onRemove: () => notifier.removeLine(e.key),
            onProduct: (p) => notifier.updateLine(
              e.key,
              e.value.copyWith(
                productId: p.id,
                productName: p.name,
                description: p.name,
                rate: p.purchasePrice,
                gstRate: p.gstRate,
                hsnSac: p.hsnSac,
              ),
            ),
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: BarcodeProductField(
              label:
                  'Scan received item barcode (repeated scans increase quantity)',
              onProduct: notifier.addScannedProduct,
            ),
          ),
          if (ResponsiveLayout.isMobile(context))
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: lineTable,
            )
          else
            lineTable,
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton.icon(
                onPressed: notifier.addLine,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add line  (Alt+N)'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionsCard(
    BillFormState state,
    BillFormNotifier notifier,
    ApexColors colors,
    bool gstEnabled,
  ) {
    return _Card(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 200,
                child: _labeled(
                  'TDS Rate (%)',
                  TextField(
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: _dec(
                      colors,
                      hint: 'e.g. 1',
                      icon: Icons.percent_rounded,
                    ),
                    onChanged: (v) =>
                        notifier.setTdsRate(double.tryParse(v) ?? 0),
                  ),
                  colors,
                ),
              ),
              if (gstEnabled) ...[
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ITC ELIGIBLE',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Switch(
                      value: state.itcEligible,
                      onChanged: notifier.setItcEligible,
                      activeThumbColor: colors.primary,
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _labeled(
            'Notes',
            TextField(
              maxLines: 3,
              decoration: _dec(colors, hint: 'Optional notes…'),
              onChanged: notifier.setNotes,
            ),
            colors,
          ),
        ],
      ),
    );
  }

  Widget _totalsBar(
    BillFormState state,
    ApexColors colors,
    NumberFormatter fmt,
    bool gstEnabled,
  ) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final netPayable = state.total - state.tdsAmount;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(top: BorderSide(color: colors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
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
                Row(
                  children: [
                    Text(
                      '${state.lines.where((l) => l.productId.isNotEmpty).length} item(s)',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                    const Spacer(),
                    _tot(
                      'Net Payable',
                      fmt.currency(netPayable),
                      colors,
                      emphasize: true,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _tot('Subtotal', fmt.currency(state.subtotal), colors),
                    if (gstEnabled)
                      _tot('Tax', fmt.currency(state.totalTax), colors),
                    if (state.tdsRate > 0)
                      _tot('TDS', fmt.currency(state.tdsAmount), colors),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Text(
                  '${state.lines.where((l) => l.productId.isNotEmpty).length} item(s)',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
                const Spacer(),
                _tot('Subtotal', fmt.currency(state.subtotal), colors),
                _sep(colors),
                if (state.discountTotal > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _tot(
                      'Discount',
                      '- ${fmt.currency(state.discountTotal)}',
                      colors,
                    ),
                  ),
                if (state.cgstAmount > 0) ...[
                  _tot('CGST', fmt.currency(state.cgstAmount), colors),
                  _sep(colors),
                ],
                if (state.sgstAmount > 0) ...[
                  _tot('SGST', fmt.currency(state.sgstAmount), colors),
                  _sep(colors),
                ],
                if (state.igstAmount > 0) ...[
                  _tot('IGST', fmt.currency(state.igstAmount), colors),
                  _sep(colors),
                ],
                if (gstEnabled) ...[
                  _tot('Tax', fmt.currency(state.totalTax), colors),
                  _sep(colors),
                ],
                if (state.tdsRate > 0) ...[
                  _tot('TDS', fmt.currency(state.tdsAmount), colors),
                  _sep(colors),
                ],
                _tot('Total', fmt.currency(state.total), colors),
                _sep(colors),
                _tot(
                  'Net Payable',
                  fmt.currency(netPayable),
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
                  label: const Text('Save Bill  (Ctrl+S)'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
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
          fontSize: emphasize ? 20 : 15,
          fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
          color: emphasize ? colors.primary : colors.textPrimary,
        ),
      ),
    ],
  );

  Widget _sep(ApexColors colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Container(width: 1, height: 34, color: colors.border),
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
}

// ---------------------------------------------------------------------------
// Reusable widgets
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.colors, required this.child, this.padding});
  final ApexColors colors;
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) =>
      ApexCard(padding: padding ?? const EdgeInsets.all(20), child: child);
}

class _HCell extends StatelessWidget {
  const _HCell(this.label, {required this.flex, this.right = false});
  final String label;
  final int flex;
  final bool right;
  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: colors.textMuted,
        ),
      ),
    );
  }
}

class _VendorField extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    return Autocomplete<Contact>(
      displayStringForOption: (c) => c.name,
      optionsBuilder: (v) async {
        return searchContactOptions(
          repository: ref.read(contactRepositoryProvider),
          localContacts: contacts,
          type: ContactType.vendor,
          query: v.text,
        );
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, ctrl, fn, onSubmit) {
        if (selectedName.isNotEmpty && ctrl.text.isEmpty) {
          ctrl.text = selectedName;
        }
        Future<void> createParty() async {
          final created = await showQuickCreateParty(
            context,
            contactType: ContactType.vendor,
            initialName: ctrl.text,
          );
          if (created != null) {
            ctrl.text = created.name;
            onSelected(created);
            focusNode.requestFocus();
          }
        }

        final canCreate = ref.watch(
          permissionProvider(Permissions.contactCreate),
        );
        return Row(
          children: [
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  if (canCreate)
                    const SingleActivator(LogicalKeyboardKey.keyC, alt: true):
                        createParty,
                },
                child: TextField(
                  controller: ctrl,
                  focusNode: focusNode,
                  decoration: _dec(
                    colors,
                    hint: 'Search vendor or GSTIN…',
                    icon: Icons.storefront_outlined,
                  ),
                ),
              ),
            ),
            if (canCreate)
              IconButton(
                tooltip: 'New vendor (Alt+C)',
                onPressed: createParty,
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
          ],
        );
      },
      optionsViewBuilder: (context, onSel, options) => _optionsPanel<Contact>(
        context,
        colors,
        options,
        onSel,
        (c) => c.name,
        (c) => c.gstin ?? c.email ?? '',
      ),
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

class _BillLineRow extends StatefulWidget {
  const _BillLineRow({
    super.key,
    required this.line,
    required this.products,
    required this.colors,
    required this.fmt,
    required this.gstEnabled,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
    required this.onProduct,
  });
  final BillLine line;
  final List<Product> products;
  final ApexColors colors;
  final NumberFormatter fmt;
  final bool gstEnabled;
  final bool canRemove;
  final void Function(BillLine) onChanged;
  final VoidCallback onRemove;
  final void Function(Product) onProduct;
  @override
  State<_BillLineRow> createState() => _BillLineRowState();
}

class _BillLineRowState extends State<_BillLineRow> {
  late final TextEditingController _qty;
  late final TextEditingController _rate;
  late final TextEditingController _disc;

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(text: _num(widget.line.quantity));
    _rate = TextEditingController(text: _num(widget.line.rate));
    _disc = TextEditingController(text: _num(widget.line.discount));
  }

  @override
  void didUpdateWidget(_BillLineRow old) {
    super.didUpdateWidget(old);
    _syncIfChanged(_rate, widget.line.rate, old.line.rate);
    _syncIfChanged(_qty, widget.line.quantity, old.line.quantity);
    _syncIfChanged(_disc, widget.line.discount, old.line.discount);
  }

  void _syncIfChanged(TextEditingController c, double now, double before) {
    if (now != before && (double.tryParse(c.text) ?? 0) != now) {
      c.text = _num(now);
    }
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _qty.dispose();
    _rate.dispose();
    _disc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final isMobile = ResponsiveLayout.isMobile(context);
    if (isMobile) return _buildMobileLine(c);
    return _buildDesktopLine(c);
  }

  Widget _buildDesktopLine(ApexColors c) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 34,
            child: _ProductField(
              products: widget.products,
              current: widget.line.productName ?? widget.line.description ?? '',
              colors: c,
              onSelected: widget.onProduct,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 12,
            child: Text(
              widget.line.hsnSac.isEmpty ? '—' : widget.line.hsnSac,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 10,
            child: _numField(
              _qty,
              onChanged: (v) => widget.onChanged(
                widget.line.copyWith(quantity: double.tryParse(v) ?? 0),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 14,
            child: _numField(
              _rate,
              onChanged: (v) => widget.onChanged(
                widget.line.copyWith(rate: double.tryParse(v) ?? 0),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 10,
            child: _numField(
              _disc,
              onChanged: (v) => widget.onChanged(
                widget.line.copyWith(discount: double.tryParse(v) ?? 0),
              ),
            ),
          ),
          if (widget.gstEnabled) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 10,
              child: Text(
                '${_num(widget.line.gstRate)}%',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            flex: 14,
            child: Text(
              widget.fmt.currency(widget.line.total),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.close_rounded,
                size: 16,
                color: widget.canRemove ? c.textMuted : c.border,
              ),
              onPressed: widget.canRemove ? widget.onRemove : null,
              tooltip: 'Remove line',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLine(ApexColors c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(ApexRadius.lg),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.line.productName ??
                        widget.line.description ??
                        'Item',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.line.productId.isNotEmpty
                          ? c.textPrimary
                          : c.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.canRemove)
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: c.danger),
                    onPressed: widget.onRemove,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: _ProductField(
              products: widget.products,
              current: widget.line.productName ?? widget.line.description ?? '',
              colors: c,
              onSelected: widget.onProduct,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: _pMobileField(
                    c,
                    'QTY',
                    _qty,
                    onChanged: (v) => widget.onChanged(
                      widget.line.copyWith(quantity: double.tryParse(v) ?? 0),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _pMobileField(
                    c,
                    'RATE',
                    _rate,
                    onChanged: (v) => widget.onChanged(
                      widget.line.copyWith(rate: double.tryParse(v) ?? 0),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _pMobileField(
                    c,
                    'DISC%',
                    _disc,
                    onChanged: (v) => widget.onChanged(
                      widget.line.copyWith(discount: double.tryParse(v) ?? 0),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              children: [
                if (widget.gstEnabled)
                  Text(
                    'GST ${widget.line.gstRate.toInt()}%',
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                const Spacer(),
                Text(
                  widget.fmt.currency(widget.line.total),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pMobileField(
    ApexColors c,
    String label,
    TextEditingController ctrl, {
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: c.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ApexRadius.sm),
              borderSide: BorderSide(color: c.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ApexRadius.sm),
              borderSide: BorderSide(color: c.primary, width: 1.5),
            ),
            filled: true,
            fillColor: c.surfaceMuted,
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _numField(
    TextEditingController ctrl, {
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: ctrl,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ApexRadius.sm),
        ),
      ),
      onChanged: onChanged,
    );
  }
}

class _ProductField extends ConsumerWidget {
  const _ProductField({
    required this.products,
    required this.current,
    required this.colors,
    required this.onSelected,
  });
  final List<Product> products;
  final String current;
  final ApexColors colors;
  final void Function(Product) onSelected;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Autocomplete<Product>(
      displayStringForOption: (p) => p.name,
      optionsBuilder: (v) async {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return products.take(8);
        final result = await ref
            .read(productRepositoryProvider)
            .list(ListQuery(search: q, limit: 12));
        return result.dataOrNull?.items ?? const <Product>[];
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, ctrl, fn, onSubmit) {
        if (current.isNotEmpty && ctrl.text.isEmpty) ctrl.text = current;
        Future<void> createItem() async {
          final created = await showQuickCreateItem(
            context,
            initialName: ctrl.text,
            purchaseContext: true,
          );
          if (created != null) {
            ctrl.text = created.name;
            onSelected(created);
            fn.requestFocus();
          }
        }

        final canCreate = ref.watch(
          permissionProvider(Permissions.invoiceCreate),
        );
        return Row(
          children: [
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  if (canCreate)
                    const SingleActivator(LogicalKeyboardKey.keyC, alt: true):
                        createItem,
                },
                child: TextField(
                  controller: ctrl,
                  focusNode: fn,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search item…',
                    prefixIcon: Icon(
                      Icons.inventory_2_outlined,
                      size: 16,
                      color: colors.textMuted,
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 32),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ApexRadius.sm),
                    ),
                  ),
                ),
              ),
            ),
            if (canCreate)
              IconButton(
                tooltip: 'New item (Alt+C)',
                onPressed: createItem,
                icon: const Icon(Icons.add_box_outlined),
              ),
          ],
        );
      },
      optionsViewBuilder: (context, onSel, options) => _optionsPanel<Product>(
        context,
        colors,
        options,
        onSel,
        (p) => p.name,
        (p) =>
            '${p.sku ?? ''}${p.barcode == null ? '' : '  ·  ${p.barcode}'}  ·  ${p.hsnSac}  ·  GST ${p.gstRate.toInt()}%',
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

Widget _optionsPanel<T extends Object>(
  BuildContext context,
  ApexColors colors,
  Iterable<T> options,
  void Function(T) onSelected,
  String Function(T) title,
  String Function(T) subtitle,
) {
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
                onTap: () => onSelected(o),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title(o),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (subtitle(o).trim().isNotEmpty)
                        Text(
                          subtitle(o),
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
}
