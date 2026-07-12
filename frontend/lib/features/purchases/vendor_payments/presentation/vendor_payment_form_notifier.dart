/// Vendor payment form notifier — loads outstanding bills, auto-suggests
/// allocations, and creates the payment. Reuses existing services (no new API).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/outstanding_bill.dart';
import '../models/vendor_payment.dart';
import '../models/vendor_payment_enums.dart';
import '../services/vendor_payment_service.dart';
import '../services/payable_allocation_service.dart';
import '../services/vendor_payment_validation_service.dart';
import 'vendor_payment_form_state.dart';

class VendorPaymentFormNotifier extends StateNotifier<VendorPaymentFormState> {
  VendorPaymentFormNotifier(this._service, this._alloc, this._validation)
    : super(const VendorPaymentFormState());

  final VendorPaymentService _service;
  final PayableAllocationService _alloc;
  final VendorPaymentValidationService _validation;

  void setPaymentNumber(String v) => state = state.copyWith(paymentNumber: v);
  void setPaymentDate(String d) => state = state.copyWith(paymentDate: d);
  void setPaymentMode(PaymentMode m) => state = state.copyWith(paymentMode: m);
  void setReference(String r) => state = state.copyWith(referenceNumber: r);

  Future<void> selectVendor(String id, String name) async {
    state = state.copyWith(
      contactId: id,
      contactName: name,
      loadingBills: true,
      allocations: {},
      clearError: true,
    );
    final res = await _service.outstandingBills(id);
    switch (res) {
      case Success<List<OutstandingBill>>(:final value):
        state = state.copyWith(bills: value, loadingBills: false);
        _reallocate();
      case Failure(:final error):
        state = state.copyWith(loadingBills: false, error: error.message);
      default:
        state = state.copyWith(loadingBills: false);
    }
  }

  void setAmount(double amount) {
    state = state.copyWith(amount: amount);
    _reallocate();
  }

  /// Auto-distribute the payment amount across outstanding bills (oldest first).
  void autoAllocate() => _reallocate();

  void _reallocate() {
    if (state.bills.isEmpty || state.amount <= 0) return;
    final suggested = _alloc.suggestAllocations(
      bills: state.bills,
      paymentAmount: state.amount,
    );
    state = state.copyWith(
      allocations: {for (final a in suggested) a.billId: a.amount},
    );
  }

  void setAllocation(String billId, double amount) {
    final map = Map<String, double>.from(state.allocations);
    if (amount <= 0) {
      map.remove(billId);
    } else {
      map[billId] = amount;
    }
    state = state.copyWith(allocations: map);
  }

  Future<VendorPayment?> create() async {
    state = state.copyWith(saving: true, clearError: true);
    // Cross-check allocations against outstanding balances via the pure engine.
    final allocErr = _alloc.validateAllocations(
      bills: state.bills,
      allocations: state.allocationList,
      paymentAmount: state.amount,
    );
    if (allocErr != null) {
      state = state.copyWith(saving: false, error: allocErr);
      return null;
    }
    final payment = VendorPayment(
      id: '',
      paymentNumber: state.paymentNumber.trim(),
      contactId: state.contactId ?? '',
      contactName: state.contactName,
      paymentDate: state.paymentDate,
      paymentMode: state.paymentMode,
      amount: state.amount,
      referenceNumber: state.referenceNumber,
      allocations: state.allocationList,
    );
    final err = _validation.validateForCreate(payment);
    if (err != null) {
      state = state.copyWith(saving: false, error: err);
      return null;
    }
    final result = await _service.create(payment);
    state = state.copyWith(saving: false);
    if (result is Success<VendorPayment>) return result.value;
    if (result is Failure<VendorPayment>) {
      state = state.copyWith(error: result.error.message);
    }
    return null;
  }
}

final vendorPaymentFormProvider =
    StateNotifierProvider.autoDispose<
      VendorPaymentFormNotifier,
      VendorPaymentFormState
    >((ref) {
      return VendorPaymentFormNotifier(
        ref.watch(vendorPaymentServiceProvider),
        const PayableAllocationService(),
        const VendorPaymentValidationService(),
      );
    });
