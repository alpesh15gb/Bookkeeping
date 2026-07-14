/// Delivery Challan form with customer, products, and issue workflow.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/dialogs/dialog_service.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/features/masters/contacts/presentation/contact_controller.dart';
import 'package:apexbooks/features/masters/contacts/data/models/contact.dart';
import 'package:apexbooks/features/masters/products/presentation/product_controller.dart';
import 'package:apexbooks/features/masters/products/data/models/product.dart';
import 'package:apexbooks/features/masters/shared/presentation/quick_create_dialogs.dart';
import 'package:apexbooks/features/sales/models/invoice_line.dart';

// ---------------------------------------------------------------------------
// Form state
// ---------------------------------------------------------------------------

class DeliveryChallanFormState {
  const DeliveryChallanFormState({
    this.contactId,
    this.contactName = '',
    this.challanDate = '',
    this.dueDate = '',
    this.posStateCode = '',
    this.lines = const [],
    this.subtotal = 0,
    this.discountTotal = 0,
    this.totalTax = 0,
    this.total = 0,
    this.saving = false,
    this.error,
  });

  final String? contactId;
  final String contactName;
  final String challanDate;
  final String dueDate;
  final String posStateCode;
  final List<InvoiceLine> lines;
  final double subtotal;
  final double discountTotal;
  final double totalTax;
  final double total;
  final bool saving;
  final String? error;

  bool get isValid =>
      contactId != null && lines.any((l) => l.productId.isNotEmpty);

  DeliveryChallanFormState copyWith({
    String? contactId,
    String? contactName,
    String? challanDate,
    String? dueDate,
    String? posStateCode,
    List<InvoiceLine>? lines,
    double? subtotal,
    double? discountTotal,
    double? totalTax,
    double? total,
    bool? saving,
    String? error,
    bool clearError = false,
  }) => DeliveryChallanFormState(
    contactId: contactId ?? this.contactId,
    contactName: contactName ?? this.contactName,
    challanDate: challanDate ?? this.challanDate,
    dueDate: dueDate ?? this.dueDate,
    posStateCode: posStateCode ?? this.posStateCode,
    lines: lines ?? this.lines,
    subtotal: subtotal ?? this.subtotal,
    discountTotal: discountTotal ?? this.discountTotal,
    totalTax: totalTax ?? this.totalTax,
    total: total ?? this.total,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
  );
}

// ---------------------------------------------------------------------------
// Calculation helpers
// ---------------------------------------------------------------------------

({List<InvoiceLine> lines, double subtotal, double discountTotal, double total})
_dcCalculateAll(List<InvoiceLine> lines) {
  double subtotal = 0;
  double discountTotal = 0;
  final updated = lines.map((l) {
    final lineSubtotal = l.quantity * l.rate;
    final disc = l.discount;
    final lineTotal = lineSubtotal - disc;
    subtotal += lineSubtotal;
    discountTotal += disc;
    return l.copyWith(subtotal: lineTotal, total: lineTotal);
  }).toList();
  return (
    lines: updated,
    subtotal: subtotal,
    discountTotal: discountTotal,
    total: subtotal - discountTotal,
  );
}

// ---------------------------------------------------------------------------
// Form notifier
// ---------------------------------------------------------------------------

class DeliveryChallanFormNotifier
    extends StateNotifier<DeliveryChallanFormState> {
  DeliveryChallanFormNotifier(this._dio)
    : super(
        const DeliveryChallanFormState(
          lines: [InvoiceLine(productId: '', hsnSac: '', gstRate: 18)],
        ),
      );

  final Dio _dio;

  Future<void> loadForEdit(String id) async {
    try {
      final res = await _dio.get('/delivery-challans/$id');
      final json = res.data as Map<String, dynamic>;
      final contactName = json['contact_name'] as String? ?? '';
      final lines =
          (json['lines'] as List?)
              ?.map((e) => InvoiceLine.fromResponse(e as Map<String, dynamic>))
              .toList() ??
          [];
      state = DeliveryChallanFormState(
        contactId: (json['contact_id'] ?? '').toString(),
        contactName: contactName,
        challanDate: json['challan_date'] as String? ?? '',
        dueDate: json['due_date'] as String? ?? '',
        posStateCode: json['pos_state_code'] as String? ?? '',
        lines: lines,
        subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
        discountTotal: (json['discount_total'] as num?)?.toDouble() ?? 0,
        totalTax:
            ((json['cgst_amount'] as num?)?.toDouble() ?? 0) +
            ((json['sgst_amount'] as num?)?.toDouble() ?? 0) +
            ((json['igst_amount'] as num?)?.toDouble() ?? 0),
        total: (json['total'] as num?)?.toDouble() ?? 0,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        error: e.message ?? 'Failed to load delivery challan',
      );
    }
  }

  void setContact(String id, String name) =>
      state = state.copyWith(contactId: id, contactName: name);
  void setChallanDate(String d) => state = state.copyWith(challanDate: d);
  void setDueDate(String d) => state = state.copyWith(dueDate: d);
  void setPosStateCode(String c) => state = state.copyWith(posStateCode: c);

  void updateLine(int index, InvoiceLine line) {
    final lines = [...state.lines]..[index] = line;
    _recalc(state.copyWith(lines: lines));
  }

  void addLine() {
    _recalc(
      state.copyWith(
        lines: [
          ...state.lines,
          const InvoiceLine(productId: '', hsnSac: '', gstRate: 18),
        ],
      ),
    );
  }

  void removeLine(int index) {
    if (state.lines.length <= 1) return;
    _recalc(state.copyWith(lines: [...state.lines]..removeAt(index)));
  }

  void _recalc(DeliveryChallanFormState s) {
    final r = _dcCalculateAll(s.lines);
    state = s.copyWith(
      lines: r.lines,
      subtotal: r.subtotal,
      discountTotal: r.discountTotal,
      total: r.total,
    );
  }

  Future<bool> create() async {
    state = state.copyWith(saving: true, error: null, clearError: true);
    if (state.contactId == null) {
      state = state.copyWith(saving: false, error: 'Please select a customer.');
      return false;
    }
    if (!state.lines.any((l) => l.productId.isNotEmpty)) {
      state = state.copyWith(
        saving: false,
        error: 'Please add at least one line item.',
      );
      return false;
    }
    try {
      await _dio.post('/delivery-challans', data: _buildPayload());
      state = state.copyWith(saving: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(
        saving: false,
        error:
            e.response?.data?['detail']?.toString() ??
            e.message ??
            'Failed to save',
      );
      return false;
    }
  }

  Future<bool> update(String id) async {
    state = state.copyWith(saving: true, error: null, clearError: true);
    try {
      await _dio.put('/delivery-challans/$id', data: _buildPayload());
      state = state.copyWith(saving: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(
        saving: false,
        error:
            e.response?.data?['detail']?.toString() ??
            e.message ??
            'Failed to update',
      );
      return false;
    }
  }

  Map<String, dynamic> _buildPayload() => {
    'contact_id': state.contactId,
    'challan_date': state.challanDate,
    'due_date': state.dueDate,
    'pos_state_code': state.posStateCode,
    'line_items': state.lines.map((l) => l.toCreatePayload()).toList(),
  };
}

final deliveryChallanFormProvider =
    StateNotifierProvider.autoDispose<
      DeliveryChallanFormNotifier,
      DeliveryChallanFormState
    >((ref) => DeliveryChallanFormNotifier(ref.watch(apiClientProvider)));

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class DeliveryChallanFormScreen extends ConsumerStatefulWidget {
  const DeliveryChallanFormScreen({super.key, this.editId});
  final String? editId;

  @override
  ConsumerState<DeliveryChallanFormScreen> createState() =>
      _DeliveryChallanFormScreenState();
}

class _DeliveryChallanFormScreenState
    extends ConsumerState<DeliveryChallanFormScreen> {
  final _customerFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(contactControllerProvider.notifier)
          .load(const ListQuery(limit: 100));
      ref
          .read(productControllerProvider.notifier)
          .load(const ListQuery(limit: 100));
      final now = DateTime.now();
      if (widget.editId != null) {
        ref
            .read(deliveryChallanFormProvider.notifier)
            .loadForEdit(widget.editId!);
      } else {
        final n = ref.read(deliveryChallanFormProvider.notifier);
        n.setChallanDate(_fmtDate(now));
        n.setDueDate(_fmtDate(now.add(const Duration(days: 30))));
        _customerFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _customerFocus.dispose();
    super.dispose();
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime? _parseDate(String s) => DateTime.tryParse(s);

  bool get _hasUnsavedChanges {
    final s = ref.read(deliveryChallanFormProvider);
    return s.contactId != null || s.lines.any((l) => l.productId.isNotEmpty);
  }

  Future<void> _save() async {
    final notifier = ref.read(deliveryChallanFormProvider.notifier);
    if (ref.read(deliveryChallanFormProvider).saving) return;
    final ok = widget.editId != null
        ? await notifier.update(widget.editId!)
        : await notifier.create();
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deliveryChallanFormProvider);
    final notifier = ref.read(deliveryChallanFormProvider.notifier);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    final contactsState = ref.watch(contactControllerProvider);
    final contactsList = contactsState is ListData<Contact>
        ? contactsState.paged.items
        : <Contact>[];
    final productsState = ref.watch(productControllerProvider);
    final productsList = productsState is ListData<Product>
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
              scrolledUnderElevation: 0.5,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: Text(
                widget.editId != null ? 'Edit Challan' : 'New delivery challan',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
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
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
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
                    label: const Text('Save draft'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
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
                      horizontal: 16,
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
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: 3,
                        itemBuilder: (context, idx) {
                          switch (idx) {
                            case 0:
                              return _headerCard(
                                state,
                                notifier,
                                colors,
                                contactsList,
                              );
                            case 1:
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _linesCard(
                                  state,
                                  notifier,
                                  colors,
                                  fmt,
                                  productsList,
                                ),
                              );
                            case 2:
                              return const SizedBox(height: 80);
                            default:
                              return const SizedBox.shrink();
                          }
                        },
                      ),
                    ),
                  ),
                ),
                _totalsBar(context, state, colors, fmt),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header: customer + dates ────────────────────────────────────────────
  Widget _headerCard(
    DeliveryChallanFormState state,
    DeliveryChallanFormNotifier notifier,
    ApexColors colors,
    List<Contact> contacts,
  ) {
    return _Card(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 720;
              final customer = _labeled(
                'Customer',
                _CustomerField(
                  focusNode: _customerFocus,
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
                flex: 2,
                required: true,
              );
              final order = _labeled(
                'Challan date',
                _DateField(
                  value: state.challanDate,
                  colors: colors,
                  onPick: (d) => notifier.setChallanDate(_fmtDate(d)),
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
              if (narrow) {
                return Column(
                  children: [
                    customer,
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: order),
                        const SizedBox(width: 12),
                        Expanded(child: due),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: customer),
                  const SizedBox(width: 16),
                  Expanded(child: order),
                  const SizedBox(width: 16),
                  Expanded(child: due),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Line item grid ──────────────────────────────────────────────────────
  Widget _linesCard(
    DeliveryChallanFormState state,
    DeliveryChallanFormNotifier notifier,
    ApexColors colors,
    NumberFormatter fmt,
    List<Product> products,
  ) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final lineTable = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isMobile)
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(ApexRadius.lg),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Row(
              children: [
                _HCell('ITEM', flex: 34),
                _HCell('HSN', flex: 12),
                _HCell('QTY', flex: 10, right: true),
                _HCell('RATE', flex: 14, right: true),
                _HCell('DISC%', flex: 10, right: true),
                _HCell('GST%', flex: 10, right: true),
                _HCell('AMOUNT', flex: 14, right: true),
                SizedBox(width: 36),
              ],
            ),
          ),
        ...state.lines.asMap().entries.map(
          (e) => _LineRow(
            key: ValueKey('dc_line_${e.key}'),
            index: e.key,
            line: e.value,
            products: products,
            colors: colors,
            fmt: fmt,
            canRemove: state.lines.length > 1,
            onChanged: (l) => notifier.updateLine(e.key, l),
            onRemove: () => notifier.removeLine(e.key),
            onProduct: (p) => notifier.updateLine(
              e.key,
              e.value.copyWith(
                productId: p.id,
                productName: p.name,
                description: p.name,
                rate: p.salesPrice,
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
          lineTable,
          Padding(
            padding: EdgeInsets.all(isMobile ? 8 : 8),
            child: isMobile
                ? SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: notifier.addLine,
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Add Item'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  )
                : TextButton.icon(
                    onPressed: notifier.addLine,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add line  (Alt+N)'),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Sticky totals bar ───────────────────────────────────────────────────
  Widget _totalsBar(
    BuildContext context,
    DeliveryChallanFormState state,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final isMobile = ResponsiveLayout.isMobile(context);
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
                      'Total',
                      fmt.currency(state.total),
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
                    _tot('Discount', fmt.currency(state.discountTotal), colors),
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
                _tot('Discount', fmt.currency(state.discountTotal), colors),
                _sep(colors),
                _tot(
                  'Total',
                  fmt.currency(state.total),
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
                  label: const Text('Save draft  (Ctrl+S)'),
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
      MonetaryText(
        value: value,
        fontSize: emphasize ? 20 : 15,
        fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
        color: emphasize ? colors.primary : colors.textPrimary,
      ),
    ],
  );

  Widget _sep(ApexColors colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Container(width: 1, height: 34, color: colors.border),
  );

  Widget _labeled(
    String label,
    Widget field,
    ApexColors colors, {
    int flex = 1,
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

// ── Shared building blocks ────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.colors, required this.child, this.padding});
  final ApexColors colors;
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return ApexCard(
      padding: padding ?? EdgeInsets.all(isMobile ? 12 : 20),
      child: child,
    );
  }
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

// ── Customer typeahead ───────────────────────────────────────────────────────

class _CustomerField extends StatelessWidget {
  const _CustomerField({
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
    final isMobile = ResponsiveLayout.isMobile(context);
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
        if (selectedName.isNotEmpty && ctrl.text.isEmpty) {
          ctrl.text = selectedName;
        }
        Future<void> createParty() async {
          final created = await showQuickCreateParty(
            context,
            contactType: ContactType.customer,
            initialName: ctrl.text,
          );
          if (created != null) {
            ctrl.text = created.name;
            onSelected(created);
            focusNode.requestFocus();
          }
        }

        return Row(
          children: [
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.keyC, alt: true):
                      createParty,
                },
                child: TextField(
                  controller: ctrl,
                  focusNode: focusNode,
                  style: TextStyle(fontSize: isMobile ? 15 : 14),
                  decoration: _dec(
                    colors,
                    hint: 'Search customer or GSTIN…',
                    icon: Icons.person_search_rounded,
                    isMobile: isMobile,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'New customer (Alt+C)',
              onPressed: createParty,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          ],
        );
      },
      optionsViewBuilder: (context, onSelected, options) =>
          _optionsPanel<Contact>(
            context,
            colors,
            options,
            onSelected,
            (c) => c.name,
            (c) => c.gstin ?? c.email ?? '',
          ),
    );
  }
}

// ── Date field ───────────────────────────────────────────────────────────────

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

// ── Line row ─────────────────────────────────────────────────────────────────

class _LineRow extends StatefulWidget {
  const _LineRow({
    super.key,
    required this.index,
    required this.line,
    required this.products,
    required this.colors,
    required this.fmt,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
    required this.onProduct,
  });
  final int index;
  final InvoiceLine line;
  final List<Product> products;
  final ApexColors colors;
  final NumberFormatter fmt;
  final bool canRemove;
  final void Function(InvoiceLine) onChanged;
  final VoidCallback onRemove;
  final void Function(Product) onProduct;
  @override
  State<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<_LineRow> {
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
  void didUpdateWidget(_LineRow old) {
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

  Widget _buildMobileLine(ApexColors c) {
    final lineNum = widget.index + 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
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
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(ApexRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$lineNum',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: c.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.line.productName ??
                        widget.line.description ??
                        'Item #$lineNum',
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
                    tooltip: 'Remove',
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
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: _mobileField(
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
                  child: _mobileField(
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
                  child: _mobileField(
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
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                _chip(
                  c,
                  'HSN',
                  widget.line.hsnSac.isEmpty ? '—' : widget.line.hsnSac,
                ),
                const SizedBox(width: 8),
                _chip(c, 'GST', '${widget.line.gstRate.toInt()}%'),
                const Spacer(),
                MonetaryText(
                  value: widget.fmt.currency(widget.line.total),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLine(ApexColors c) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
              right: true,
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
              right: true,
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
              right: true,
              onChanged: (v) => widget.onChanged(
                widget.line.copyWith(discount: double.tryParse(v) ?? 0),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 10,
            child: Text(
              '${_num(widget.line.gstRate)}%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 14,
            child: MonetaryText(
              value: widget.fmt.currency(widget.line.total),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
              textAlign: TextAlign.right,
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

  Widget _numField(
    TextEditingController ctrl, {
    required bool right,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: ctrl,
      textAlign: right ? TextAlign.right : TextAlign.left,
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

  Widget _mobileField(
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
            enabledBorder: OutlineInputBorder(
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

  Widget _chip(ApexColors c, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(ApexRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: c.textMuted,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Product typeahead ────────────────────────────────────────────────────────

class _ProductField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return Autocomplete<Product>(
      displayStringForOption: (p) => p.name,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return products.take(8);
        return products
            .where(
              (p) =>
                  p.name.toLowerCase().contains(q) ||
                  (p.sku ?? '').toLowerCase().contains(q) ||
                  p.hsnSac.toLowerCase().contains(q),
            )
            .take(12);
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, ctrl, fn, onSubmit) {
        if (current.isNotEmpty && ctrl.text.isEmpty) ctrl.text = current;
        Future<void> createItem() async {
          final created = await showQuickCreateItem(
            context,
            initialName: ctrl.text,
          );
          if (created != null) {
            ctrl.text = created.name;
            onSelected(created);
            fn.requestFocus();
          }
        }

        return Row(
          children: [
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.keyC, alt: true):
                      createItem,
                },
                child: TextField(
                  controller: ctrl,
                  focusNode: fn,
                  style: TextStyle(fontSize: isMobile ? 15 : 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search item…',
                    prefixIcon: Icon(
                      Icons.inventory_2_outlined,
                      size: isMobile ? 20 : 16,
                      color: colors.textMuted,
                    ),
                    prefixIconConstraints: BoxConstraints(
                      minWidth: isMobile ? 40 : 32,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 8,
                      vertical: isMobile ? 14 : 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ApexRadius.sm),
                    ),
                  ),
                ),
              ),
            ),
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
        (p) => '${p.sku ?? ''}  ·  ${p.hsnSac}  ·  GST ${p.gstRate.toInt()}%',
      ),
    );
  }
}

// ── Shared input decoration + options dropdown ───────────────────────────────

InputDecoration _dec(
  ApexColors colors, {
  String? hint,
  IconData? icon,
  bool isMobile = false,
}) => InputDecoration(
  isDense: true,
  hintText: hint,
  prefixIcon: icon == null
      ? null
      : Icon(icon, size: isMobile ? 22 : 18, color: colors.textMuted),
  contentPadding: EdgeInsets.symmetric(
    horizontal: 12,
    vertical: isMobile ? 16 : 14,
  ),
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
  final isMobile = ResponsiveLayout.isMobile(context);
  return Align(
    alignment: Alignment.topLeft,
    child: Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(ApexRadius.md),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: isMobile ? 350 : 300,
          maxWidth: isMobile ? double.infinity : 420,
        ),
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
                  padding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: isMobile ? 12 : 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title(o),
                        style: TextStyle(
                          fontSize: isMobile ? 15 : 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (subtitle(o).trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle(o),
                            style: TextStyle(
                              fontSize: isMobile ? 12 : 11,
                              color: colors.textMuted,
                            ),
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
