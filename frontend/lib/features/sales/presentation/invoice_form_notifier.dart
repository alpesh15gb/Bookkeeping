/// Invoice Form Notifier — Orchestrates create/edit with live calculations.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/invoice.dart';
import '../models/invoice_line.dart';
import '../services/invoice_service.dart';
import '../services/invoice_calculation_service.dart';
import 'invoice_form_state.dart';
import 'package:apexbooks/features/masters/products/data/models/product.dart';
import 'package:apexbooks/features/masters/contacts/data/models/contact.dart';
import 'package:apexbooks/features/auth/presentation/auth_controller.dart';

class InvoiceFormNotifier extends StateNotifier<InvoiceFormState> {
  InvoiceFormNotifier(this._service, this._calc)
    : super(
        const InvoiceFormState(
          lines: [InvoiceLine(productId: '', hsnSac: '', gstRate: 0)],
        ),
      );

  final InvoiceService _service;
  final InvoiceCalculationService _calc;
  String _originStateCode = '';

  // ───── Initialization ────────────────────────────────────────────────────

  Future<void> initializeNew() async {
    // Load origin state code for GST determination
    final authState = ref.read(authControllerProvider);
    _originStateCode = _stateCodeFromGstin(authState.activeMembership?.gstin);
    state = state.copyWith(
      issueDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 30)),
      posStateCode: _originStateCode,
      isGstInclusive: false,
      supplyType: 'DOMESTIC',
    );
    _recalculate();
  }

  String _stateCodeFromGstin(String? gstin) {
    if (gstin == null || gstin.length < 2) return '';
    return gstin.substring(0, 2);
  }

  Future<void> loadForEdit(String id) async {
    state = state.copyWith(isLoading: true);
    final result = await _service.get(id);
    switch (result) {
      case Success(:final value):
        _originStateCode = value.originStateCode ?? '';
        state = InvoiceFormState(
          contactId: value.contactId,
          contactName: value.contactName ?? '',
          invoiceNumber: value.invoiceNumber,
          issueDate: DateTime.tryParse(value.issueDate) ?? DateTime.now(),
          dueDate:
              DateTime.tryParse(value.dueDate) ??
              DateTime.now().add(const Duration(days: 30)),
          posStateCode: value.posStateCode,
          shippingCharges: value.shippingCharges,
          notes: value.notes,
          termsAndConditions: value.termsAndConditions,
          referenceNumber: value.referenceNumber,
          isGstInclusive: value.isGstInclusive,
          isRcm: value.isRcm,
          supplyType: value.supplyType,
          tdsRate: value.tdsRate,
          tcsRate: value.tcsRate,
          lines: value.lines,
          originalId: value.id,
          originalStatus: value.status,
        );
        _recalculate();
      case Failure(:final error):
        state = state.copyWith(isLoading: false, error: error.message);
      default:
        state = state.copyWith(
          isLoading: false,
          error: 'Unexpected result type',
        );
    }
  }

  // ───── Header Fields ──────────────────────────────────────────────────────

  void setContact(Contact contact) {
    state = state.copyWith(
      contactId: contact.id,
      contactName: contact.name,
      posStateCode: contact.stateCode ?? _originStateCode,
      billingAddress: _formatAddress(contact.billingAddress),
      shippingAddress: _formatAddress(contact.shippingAddress),
      contactGstNumber: contact.gstin,
      contactEmail: contact.email,
      contactPhone: contact.phone,
    );
    _recalculate();
  }

  String? _formatAddress(Address? address) {
    if (address == null) return null;
    return [
      address.street,
      address.city,
      address.state,
      address.stateCode,
      address.pincode,
    ].where((e) => e?.isNotEmpty == true).join(', ');
  }

  void clearContact() {
    state = state.copyWith(
      contactId: null,
      contactName: '',
      posStateCode: _originStateCode,
      billingAddress: null,
      shippingAddress: null,
      contactGstNumber: null,
      contactEmail: null,
      contactPhone: null,
    );
    _recalculate();
  }

  void setIssueDate(DateTime date) {
    state = state.copyWith(issueDate: date);
    // Auto-adjust due date if it's before issue date
    if (state.dueDate != null && date.isAfter(state.dueDate!)) {
      state = state.copyWith(dueDate: date.add(const Duration(days: 30)));
    }
  }

  void setDueDate(DateTime date) {
    state = state.copyWith(dueDate: date);
  }

  void setPosStateCode(String code) {
    state = state.copyWith(posStateCode: code);
    _recalculate();
  }

  void setShippingCharges(double amount) {
    state = state.copyWith(shippingCharges: amount);
    _recalculate();
  }

  void setReferenceNumber(String? ref) {
    state = state.copyWith(referenceNumber: ref);
  }

  void setNotes(String? notes) {
    state = state.copyWith(notes: notes);
  }

  void setTermsAndConditions(String? terms) {
    state = state.copyWith(termsAndConditions: terms);
  }

  void setIsGstInclusive(bool value) {
    state = state.copyWith(isGstInclusive: value);
    _recalculate();
  }

  void setIsRcm(bool value) {
    state = state.copyWith(isRcm: value);
    _recalculate();
  }

  void setSupplyType(String type) {
    state = state.copyWith(supplyType: type);
    _recalculate();
  }

  void setTdsRate(double rate) {
    state = state.copyWith(tdsRate: rate);
    _recalculate();
  }

  void setTcsRate(double rate) {
    state = state.copyWith(tcsRate: rate);
    _recalculate();
  }

  // ───── Line Management ────────────────────────────────────────────────────

  void addLine({int? index, Product? product}) {
    final newLine = _createLineFromProduct(product);
    final lines = List<InvoiceLine>.from(state.lines);
    if (index != null && index <= lines.length) {
      lines.insert(index, newLine);
    } else {
      lines.add(newLine);
    }
    state = state.copyWith(lines: lines);
    _recalculate();
  }

  void removeLine(int index) {
    if (state.lines.length <= 1) return; // Keep at least one line
    final lines = List<InvoiceLine>.from(state.lines);
    lines.removeAt(index);
    state = state.copyWith(lines: lines);
    _recalculate();
  }

  void duplicateLine(int index) {
    final lines = List<InvoiceLine>.from(state.lines);
    final line = lines[index];
    lines.insert(index + 1, line.copyWith(id: null));
    state = state.copyWith(lines: lines);
    _recalculate();
  }

  void moveLine(int oldIndex, int newIndex) {
    final lines = List<InvoiceLine>.from(state.lines);
    final line = lines.removeAt(oldIndex);
    lines.insert(newIndex, line);
    state = state.copyWith(lines: lines);
    // No recalc needed for reorder
  }

  void startLineEdit(int index) {
    state = state.copyWith(editingLineIndex: index);
  }

  void cancelLineEdit() {
    state = state.copyWith(editingLineIndex: null);
  }

  void updateLineField(int index, String field, dynamic value) {
    final lines = List<InvoiceLine>.from(state.lines);
    final line = lines[index];
    InvoiceLine updatedLine;

    switch (field) {
      case 'productId':
        updatedLine = line.copyWith(productId: value as String);
        break;
      case 'productName':
        updatedLine = line.copyWith(productName: value as String?);
        break;
      case 'description':
        updatedLine = line.copyWith(description: value as String?);
        break;
      case 'quantity':
        updatedLine = line.copyWith(quantity: (value as num).toDouble());
        break;
      case 'rate':
        updatedLine = line.copyWith(rate: (value as num).toDouble());
        break;
      case 'discount':
        updatedLine = line.copyWith(discount: (value as num).toDouble());
        break;
      case 'hsnSac':
        updatedLine = line.copyWith(hsnSac: value as String);
        break;
      case 'gstRate':
        updatedLine = line.copyWith(gstRate: (value as num).toDouble());
        break;
      case 'unit':
        updatedLine = line.copyWith(unit: value as String?);
        break;
      default:
        return;
    }

    lines[index] = updatedLine;
    state = state.copyWith(lines: lines);
    _recalculate();
  }

  void applyProductToLine(int index, Product product) {
    final lines = List<InvoiceLine>.from(state.lines);
    lines[index] = _createLineFromProduct(product, existingLine: lines[index]);
    state = state.copyWith(lines: lines, editingLineIndex: null);
    _recalculate();
  }

  InvoiceLine _createLineFromProduct(
    Product? product, {
    InvoiceLine? existingLine,
  }) {
    if (product == null) {
      return InvoiceLine(
        productId: existingLine?.productId ?? '',
        hsnSac: existingLine?.hsnSac ?? '',
        gstRate: existingLine?.gstRate ?? 0,
        quantity: existingLine?.quantity ?? 1,
        rate: existingLine?.rate ?? 0,
        discount: existingLine?.discount ?? 0,
        unit: existingLine?.unit ?? 'PCS',
      );
    }

    return InvoiceLine(
      productId: product.id,
      productName: product.name,
      description: product.sku,
      quantity: 1,
      rate: product.salesPrice,
      discount: 0,
      hsnSac: product.hsnSac,
      gstRate: product.gstRate,
      unit: product.uom,
    );
  }

  // ───── Calculations ───────────────────────────────────────────────────────

  void _recalculate() {
    if (state.lines.isEmpty) return;

    final calc = _calc.calculateAll(
      lines: state.lines,
      shippingCharges: state.shippingCharges,
      isInterState: _originStateCode != state.posStateCode,
      isGstInclusive: state.isGstInclusive,
      isRcm: state.isRcm,
    );

    final lines = calc.lines;
    final cgstAmount = lines.fold<double>(0, (s, l) => s + l.cgstAmount);
    final sgstAmount = lines.fold<double>(0, (s, l) => s + l.sgstAmount);
    final igstAmount = lines.fold<double>(0, (s, l) => s + l.igstAmount);
    final utgstAmount = lines.fold<double>(0, (s, l) => s + l.utgstAmount);
    final cessAmount = lines.fold<double>(0, (s, l) => s + l.cessAmount);
    final taxableValue =
        calc.subtotal - calc.discountTotal + state.shippingCharges;
    final taxTotal =
        cgstAmount + sgstAmount + igstAmount + utgstAmount + cessAmount;
    final roundOff = calc.total - (taxableValue + (state.isRcm ? 0 : taxTotal));

    state = state.copyWith(
      lines: lines,
      calculatedSubtotal: calc.subtotal,
      calculatedDiscountTotal: calc.discountTotal,
      calculatedTaxableValue: taxableValue,
      calculatedCgstAmount: cgstAmount,
      calculatedSgstAmount: sgstAmount,
      calculatedIgstAmount: igstAmount,
      calculatedUtgstAmount: utgstAmount,
      calculatedCessAmount: cessAmount,
      calculatedShippingCharges: state.shippingCharges,
      calculatedRoundOff: roundOff,
      calculatedTotal: calc.total,
      calculatedTaxBreakdown: _buildTaxBreakdown(
        taxableValue,
        cgstAmount,
        sgstAmount,
        igstAmount,
        utgstAmount,
        cessAmount,
      ),
      lineCalculations: _buildLineCalculations(lines),
      error: null,
    );
  }

  List<TaxBreakdownItem> _buildTaxBreakdown(
    double taxableValue,
    double cgst,
    double sgst,
    double igst,
    double utgst,
    double cess,
  ) {
    final items = <TaxBreakdownItem>[];
    if (cgst > 0) {
      items.add(
        TaxBreakdownItem(
          label: 'CGST',
          rate: 0,
          taxableValue: taxableValue,
          amount: cgst,
        ),
      );
    }
    if (sgst > 0) {
      items.add(
        TaxBreakdownItem(
          label: 'SGST',
          rate: 0,
          taxableValue: taxableValue,
          amount: sgst,
        ),
      );
    }
    if (igst > 0) {
      items.add(
        TaxBreakdownItem(
          label: 'IGST',
          rate: 0,
          taxableValue: taxableValue,
          amount: igst,
        ),
      );
    }
    if (utgst > 0) {
      items.add(
        TaxBreakdownItem(
          label: 'UTGST',
          rate: 0,
          taxableValue: taxableValue,
          amount: utgst,
        ),
      );
    }
    if (cess > 0) {
      items.add(
        TaxBreakdownItem(
          label: 'Cess',
          rate: 0,
          taxableValue: taxableValue,
          amount: cess,
        ),
      );
    }
    return items;
  }

  List<LineCalculation> _buildLineCalculations(List<InvoiceLine> lines) {
    return [
      for (int i = 0; i < lines.length; i++)
        LineCalculation(
          lineIndex: i,
          subtotal: lines[i].subtotal,
          discountAmount: lines[i].discountAmount,
          taxableValue: lines[i].subtotal - lines[i].discountAmount,
          cgstAmount: lines[i].cgstAmount,
          sgstAmount: lines[i].sgstAmount,
          igstAmount: lines[i].igstAmount,
          utgstAmount: lines[i].utgstAmount,
          cessAmount: lines[i].cessAmount,
          total: lines[i].total,
        ),
    ];
  }

  // ───── Validation & Save ──────────────────────────────────────────────────

  bool validate() {
    final errors = <String, String>{};

    if (state.contactId == null || state.contactId!.isEmpty) {
      errors['contact'] = 'Customer is required';
    }

    if (state.issueDate == null) {
      errors['issueDate'] = 'Issue date is required';
    }

    if (state.dueDate == null) {
      errors['dueDate'] = 'Due date is required';
    }

    // Validate lines
    for (int i = 0; i < state.lines.length; i++) {
      final line = state.lines[i];
      if (line.productId.isEmpty && (line.productName?.isEmpty ?? true)) {
        errors['line_${i}_product'] = 'Product/description required';
      }
      if (line.quantity <= 0) {
        errors['line_${i}_qty'] = 'Quantity must be > 0';
      }
      if (line.rate < 0) {
        errors['line_${i}_rate'] = 'Rate cannot be negative';
      }
    }

    if (errors.isNotEmpty) {
      state = state.copyWith(validationErrors: errors);
      return false;
    }

    state = state.copyWith(validationErrors: {});
    return true;
  }

  Future<Result<Invoice>> save() async {
    if (!validate()) {
      return const Failure(ApiError(message: 'Validation failed'));
    }

    state = state.copyWith(isSaving: true);

    final request = <String, dynamic>{
      'contact_id': state.contactId!,
      'invoice_number': state.invoiceNumber,
      'issue_date': state.issueDate!.toIso8601String().split('T').first,
      'due_date': state.dueDate!.toIso8601String().split('T').first,
      'pos_state_code': state.posStateCode,
      'shipping_charges': state.shippingCharges,
      'notes': state.notes,
      'terms_and_conditions': state.termsAndConditions,
      'reference_number': state.referenceNumber,
      'is_gst_inclusive': state.isGstInclusive,
      'is_rcm': state.isRcm,
      'supply_type': state.supplyType,
      'tds_rate': state.tdsRate,
      'tcs_rate': state.tcsRate,
      // The form saves drafts. Never auto-post from the form; posting is an
      // explicit workflow step. Keeps the draft out of the ledger/stock until
      // the user finalizes it.
      'post_on_create': false,
      'lines': state.lines
          .map(
            (l) => <String, dynamic>{
              'product_id': l.productId,
              'product_name': l.productName,
              'description': l.description,
              'quantity': l.quantity,
              'rate': l.rate,
              'discount': l.discount,
              'hsn_sac': l.hsnSac,
              'gst_rate': l.gstRate,
              'unit': l.unit,
            },
          )
          .toList(),
    };

    try {
      Result<Invoice> result;
      if (state.originalId != null) {
        result = await _service.update(state.originalId!, request);
      } else {
        result = await _service.create(request);
      }

      state = state.copyWith(isSaving: false);
      return result;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: e.toString());
      return Failure(ApiError(message: 'Unknown error: ${e.toString()}'));
    }
  }

  // ───── Actions ────────────────────────────────────────────────────────────

  void duplicate() {
    // Keep all fields except ID and invoice number
    state = state.copyWith(
      originalId: null,
      originalStatus: null,
      invoiceNumber: '', // Will be auto-generated
      issueDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 30)),
    );
  }

  // Riverpod ref for accessing other providers
  late final Ref ref;
}

// ───── Providers ────────────────────────────────────────────────────────────

final invoiceFormNotifierProvider =
    StateNotifierProvider<InvoiceFormNotifier, InvoiceFormState>((ref) {
      final notifier = InvoiceFormNotifier(
        ref.read(invoiceServiceProvider),
        ref.read(invoiceCalculationServiceProvider),
      );
      notifier.ref = ref;
      return notifier;
    });
