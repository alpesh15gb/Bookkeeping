/// Invoice form notifier — orchestrates create/edit with live calculations.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/invoice.dart';
import '../models/invoice_line.dart';
import '../services/invoice_service.dart';
import '../services/invoice_calculation_service.dart';
import '../services/invoice_validation_service.dart';
import 'invoice_form_state.dart';
import 'package:apexbooks/features/masters/products/data/models/product.dart';
import 'package:apexbooks/features/auth/presentation/auth_controller.dart';

class InvoiceFormNotifier extends StateNotifier<InvoiceFormState> {
  InvoiceFormNotifier(
    this._service,
    this._calc,
    this._validation,
    this._collectGst,
  ) : super(
        const InvoiceFormState(
          lines: [InvoiceLine(productId: '', hsnSac: '', gstRate: 0)],
        ),
      );

  final InvoiceService _service;
  final InvoiceCalculationService _calc;
  final InvoiceValidationService _validation;
  final bool _collectGst;
  String _originStateCode = '';

  Future<void> loadForEdit(String id) async {
    final result = await _service.get(id);
    switch (result) {
      case Success(:final value):
        state = InvoiceFormState(
          contactId: value.contactId,
          contactName: value.contactName ?? '',
          invoiceNumber: value.invoiceNumber,
          issueDate: value.issueDate,
          dueDate: value.dueDate,
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
          subtotal: value.subtotal,
          discountTotal: value.discountTotal,
          totalTax: value.totalTax,
          total: value.total,
        );
      case Failure(:final error):
        state = state.copyWith(error: error.message);
      default:
        break;
    }
  }

  void setContact(String id, String name) =>
      state = state.copyWith(contactId: id, contactName: name);
  void setIssueDate(String d) => state = state.copyWith(issueDate: d);
  void setDueDate(String d) => state = state.copyWith(dueDate: d);
  void setOriginStateCode(String c) {
    _originStateCode = c;
    _recalc(state);
  }

  void setPosStateCode(String c) => _recalc(state.copyWith(posStateCode: c));
  void setDiscountRate(double r) => _recalc(state.copyWith(discountRate: r));
  void setShipping(double s) => _recalc(state.copyWith(shippingCharges: s));
  void setIsGstInclusive(bool value) =>
      _recalc(state.copyWith(isGstInclusive: value));
  void setIsRcm(bool value) => _recalc(state.copyWith(isRcm: value));
  void setSupplyType(String value) => state = state.copyWith(supplyType: value);
  void setNotes(String n) => state = state.copyWith(notes: n);
  void setTerms(String t) => state = state.copyWith(termsAndConditions: t);
  void setRefNo(String r) => state = state.copyWith(referenceNumber: r);

  void updateLine(int index, InvoiceLine line) {
    final lines = [...state.lines]..[index] = line;
    _recalc(state.copyWith(lines: lines));
  }

  void addLine() {
    _recalc(
      state.copyWith(
        lines: [
          ...state.lines,
          const InvoiceLine(productId: '', hsnSac: '', gstRate: 0),
        ],
      ),
    );
  }

  void addScannedProduct(Product product) {
    final lines = [...state.lines];
    final existing = lines.indexWhere((line) => line.productId == product.id);
    if (existing >= 0) {
      lines[existing] = lines[existing].copyWith(
        quantity: lines[existing].quantity + 1,
      );
    } else {
      final scanned = InvoiceLine(
        productId: product.id,
        productName: product.name,
        description: product.name,
        quantity: 1,
        rate: product.salesPrice,
        gstRate: _collectGst ? product.gstRate : 0,
        hsnSac: product.hsnSac,
      );
      final empty = lines.indexWhere((line) => line.productId.isEmpty);
      if (empty >= 0) {
        lines[empty] = scanned;
      } else {
        lines.add(scanned);
      }
    }
    _recalc(state.copyWith(lines: lines, clearError: true));
  }

  void removeLine(int index) {
    if (state.lines.length <= 1) return;
    _recalc(state.copyWith(lines: [...state.lines]..removeAt(index)));
  }

  void _recalc(InvoiceFormState s) {
    final r = _calc.calculateAll(
      lines: s.lines,
      discountRate: s.discountRate,
      shippingCharges: s.shippingCharges,
      isInterState:
          _originStateCode.isNotEmpty &&
          s.posStateCode.isNotEmpty &&
          _originStateCode != s.posStateCode,
      isGstInclusive: s.isGstInclusive,
      isRcm: s.isRcm,
    );
    state = s.copyWith(
      lines: r.lines,
      subtotal: r.subtotal,
      discountTotal: r.discountTotal,
      totalTax: r.totalTax,
      total: r.total,
    );
  }

  Future<Invoice?> create() async {
    state = state.copyWith(saving: true, error: null, clearError: true);
    final check = _validation.validateForSave(
      contactId: state.contactId,
      lines: state.lines,
      posStateCode: state.posStateCode,
      issueDate: state.issueDate,
      dueDate: state.dueDate,
    );
    if (!check.$1) {
      state = state.copyWith(saving: false, error: check.$2);
      return null;
    }
    final result = await _service.create(_buildPayload());
    state = state.copyWith(saving: false);
    if (result is Success<Invoice>) return result.value;
    if (result is Failure<Invoice>) {
      debugPrint(
        'InvoiceFormNotifier.create failed (HTTP ${result.error.statusCode})'
        ' — ${result.error.message}',
      );
      state = state.copyWith(error: result.error.message);
    }
    return null;
  }

  Future<Invoice?> update(String id) async {
    state = state.copyWith(saving: true, error: null, clearError: true);
    final check = _validation.validateForSave(
      contactId: state.contactId,
      lines: state.lines,
      posStateCode: state.posStateCode,
      issueDate: state.issueDate,
      dueDate: state.dueDate,
    );
    if (!check.$1) {
      state = state.copyWith(saving: false, error: check.$2);
      return null;
    }
    final result = await _service.update(id, _buildPayload());
    state = state.copyWith(saving: false);
    if (result is Success<Invoice>) return result.value;
    if (result is Failure<Invoice>) {
      debugPrint(
        'InvoiceFormNotifier.update failed (HTTP ${result.error.statusCode})'
        ' — ${result.error.message}',
      );
      state = state.copyWith(error: result.error.message);
    }
    return null;
  }

  Map<String, dynamic> _buildPayload() => {
    'contact_id': state.contactId,
    'issue_date': state.issueDate,
    'due_date': state.dueDate,
    'pos_state_code': state.posStateCode,
    'line_items': state.lines.map((l) => l.toCreatePayload()).toList(),
    'discount_rate': state.discountRate,
    'shipping_charges': state.shippingCharges,
    if (state.notes != null) 'notes': state.notes,
    if (state.termsAndConditions != null)
      'terms_and_conditions': state.termsAndConditions,
    if (state.referenceNumber != null)
      'reference_number': state.referenceNumber,
    'is_gst_inclusive': state.isGstInclusive,
    'is_rcm': state.isRcm,
    'supply_type': state.supplyType,
    'tds_rate': state.tdsRate,
    'tcs_rate': state.tcsRate,
    'post_on_create': false,
  };
}

final invoiceFormProvider =
    StateNotifierProvider.autoDispose<InvoiceFormNotifier, InvoiceFormState>((
      ref,
    ) {
      return InvoiceFormNotifier(
        ref.watch(invoiceServiceProvider),
        const InvoiceCalculationService(),
        const InvoiceValidationService(),
        ref.watch(gstCollectionEnabledProvider),
      );
    });

final invoiceDetailProvider = FutureProvider.autoDispose
    .family<Invoice, String>((ref, id) async {
      final service = ref.watch(invoiceServiceProvider);
      final result = await service.get(id);
      return switch (result) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception('Unexpected result type'),
      };
    });
