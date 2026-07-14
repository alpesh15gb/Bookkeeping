/// Bill form notifier — create-only (backend exposes no update endpoint).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/vendor_bill.dart';
import '../models/bill_line.dart';
import '../services/vendor_bill_service.dart';
import 'bill_form_state.dart';

// ---------------------------------------------------------------------------
// Calculation engine — pure math, mirrors PO but calculates CGST/SGST/IGST
// at line level.
// ---------------------------------------------------------------------------
class _BillCalculationService {
  const _BillCalculationService();

  BillLine calculateLine({required BillLine line}) {
    final lineSubtotal = line.rate * line.quantity;
    final discountAmt = lineSubtotal * (line.discount / 100);
    final taxable = lineSubtotal - discountAmt;
    final gst = taxable * (line.gstRate / 100);
    final cgst = gst / 2;
    final sgst = gst / 2;
    final total = taxable + gst;

    return line.copyWith(
      subtotal: _round2(lineSubtotal),
      cgstRate: _round2(line.gstRate / 2),
      cgstAmount: _round2(cgst),
      sgstRate: _round2(line.gstRate / 2),
      sgstAmount: _round2(sgst),
      igstAmount: _round2(0),
      total: _round2(total),
    );
  }

  ({
    List<BillLine> lines,
    double subtotal,
    double discountTotal,
    double cgstAmount,
    double sgstAmount,
    double igstAmount,
    double totalTax,
    double total,
  })
  calculateAll({required List<BillLine> lines}) {
    final updatedLines = lines.map((l) => calculateLine(line: l)).toList();
    final subtotal = updatedLines.fold<double>(0, (s, l) => s + l.subtotal);
    final discountTotal = updatedLines.fold<double>(
      0,
      (s, l) => s + l.discountAmount,
    );
    final cgstAmount = updatedLines.fold<double>(0, (s, l) => s + l.cgstAmount);
    final sgstAmount = updatedLines.fold<double>(0, (s, l) => s + l.sgstAmount);
    final igstAmount = updatedLines.fold<double>(0, (s, l) => s + l.igstAmount);
    final totalTax = cgstAmount + sgstAmount + igstAmount;
    final total = updatedLines.fold<double>(0, (s, l) => s + l.total);
    return (
      lines: updatedLines,
      subtotal: _round2(subtotal),
      discountTotal: _round2(discountTotal),
      cgstAmount: _round2(cgstAmount),
      sgstAmount: _round2(sgstAmount),
      igstAmount: _round2(igstAmount),
      totalTax: _round2(totalTax),
      total: _round2(total),
    );
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100;
}

// ---------------------------------------------------------------------------
// Validation engine — no UI or API dependencies.
// ---------------------------------------------------------------------------
class _BillValidationService {
  const _BillValidationService();

  String? validateForSubmit(VendorBill bill) {
    if (bill.billNumber.trim().isEmpty) return 'Bill number is required';
    if (bill.contactId.isEmpty) return 'Vendor is required';
    if (bill.issueDate.isEmpty) return 'Bill date is required';
    if (bill.dueDate.isEmpty) return 'Due date is required';
    if (bill.lines.isEmpty) return 'At least one line item is required';
    if (bill.posStateCode.isEmpty) return 'State code is required';

    for (final line in bill.lines) {
      final err = _validateLine(line);
      if (err != null) return err;
    }
    return null;
  }

  String? _validateLine(BillLine line) {
    if (line.productId.isEmpty) return 'Product is required on all lines';
    if (line.quantity <= 0) return 'Quantity must be greater than zero';
    if (line.rate < 0) return 'Rate cannot be negative';
    if (line.gstRate < 0 || line.gstRate > 100) {
      return 'GST rate must be between 0 and 100';
    }
    if (line.hsnSac.isEmpty) return 'HSN/SAC is required on all lines';
    return null;
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------
class BillFormNotifier extends StateNotifier<BillFormState> {
  BillFormNotifier(this._service)
    : super(
        const BillFormState(
          lines: [BillLine(productId: '', hsnSac: '', gstRate: 18)],
        ),
      );

  final VendorBillService _service;
  final _calc = const _BillCalculationService();
  final _validation = const _BillValidationService();

  // Header fields -----------------------------------------------------------
  void setBillNumber(String v) => state = state.copyWith(billNumber: v);
  void setContact(String id, String name) =>
      state = state.copyWith(contactId: id, contactName: name);
  void setIssueDate(String d) => state = state.copyWith(issueDate: d);
  void setDueDate(String d) => state = state.copyWith(dueDate: d);
  void setReferenceNumber(String v) => state = state.copyWith(
    referenceNumber: v.isNotEmpty ? v : null,
    clearReferenceNumber: v.isEmpty,
  );
  void setPosStateCode(String c) => state = state.copyWith(posStateCode: c);

  // TDS / ITC / Notes ------------------------------------------------------
  void setTdsRate(double v) {
    final tdsAmount = state.total * (v / 100);
    state = state.copyWith(tdsRate: v, tdsAmount: _round2(tdsAmount));
  }

  void setItcEligible(bool v) => state = state.copyWith(itcEligible: v);
  void setIsGstInclusive(bool v) => state = state.copyWith(isGstInclusive: v);
  void setNotes(String v) => state = state.copyWith(
    notes: v.isNotEmpty ? v : null,
    clearNotes: v.isEmpty,
  );
  void setTerms(String v) => state = state.copyWith(
    termsAndConditions: v.isNotEmpty ? v : null,
    clearTermsAndConditions: v.isEmpty,
  );

  // Line items -------------------------------------------------------------
  void updateLine(int index, BillLine line) {
    final lines = [...state.lines]..[index] = line;
    _recalc(state.copyWith(lines: lines));
  }

  void addLine() {
    _recalc(
      state.copyWith(
        lines: [
          ...state.lines,
          const BillLine(productId: '', hsnSac: '', gstRate: 18),
        ],
      ),
    );
  }

  void removeLine(int index) {
    if (state.lines.length <= 1) return;
    _recalc(state.copyWith(lines: [...state.lines]..removeAt(index)));
  }

  void _recalc(BillFormState s) {
    final r = _calc.calculateAll(lines: s.lines);
    final tdsAmount = r.total * (s.tdsRate / 100);
    state = s.copyWith(
      lines: r.lines,
      subtotal: r.subtotal,
      discountTotal: r.discountTotal,
      cgstAmount: r.cgstAmount,
      sgstAmount: r.sgstAmount,
      igstAmount: r.igstAmount,
      totalTax: r.totalTax,
      total: r.total,
      tdsAmount: _round2(tdsAmount),
    );
  }

  // Submit -----------------------------------------------------------------
  Future<VendorBill?> create() async {
    state = state.copyWith(saving: true, clearError: true);
    final bill = VendorBill(
      id: '',
      billNumber: state.billNumber.trim(),
      contactId: state.contactId ?? '',
      contactName: state.contactName,
      issueDate: state.issueDate,
      dueDate: state.dueDate,
      posStateCode: state.posStateCode,
      referenceNumber: state.referenceNumber,
      tdsRate: state.tdsRate,
      itcEligible: state.itcEligible,
      isGstInclusive: state.isGstInclusive,
      notes: state.notes,
      termsAndConditions: state.termsAndConditions,
      lines: state.lines.where((l) => l.productId.isNotEmpty).toList(),
    );
    final err = _validation.validateForSubmit(bill);
    if (err != null) {
      state = state.copyWith(saving: false, error: err);
      return null;
    }
    final result = await _service.create(bill);
    state = state.copyWith(saving: false);
    if (result is Success<VendorBill>) return result.value;
    if (result is Failure<VendorBill>) {
      state = state.copyWith(error: result.error.message);
    }
    return null;
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final billFormProvider =
    StateNotifierProvider.autoDispose<BillFormNotifier, BillFormState>((ref) {
      return BillFormNotifier(ref.watch(vendorBillServiceProvider));
    });
