/// Payment receipt form notifier with live allocation suggestions.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/payment_models.dart';
import '../models/outstanding_invoice.dart';
import '../services/payment_service.dart';
import '../services/allocation_service.dart';
import '../services/payment_validation_service.dart';
import 'payment_form_state.dart';

class PaymentFormNotifier extends StateNotifier<PaymentFormState> {
  PaymentFormNotifier(this._service, this._allocation, this._validation)
    : super(const PaymentFormState());

  final PaymentService _service;
  final AllocationService _allocation;
  final PaymentValidationService _validation;

  void setContact(String id, String name) =>
      state = state.copyWith(contactId: id, contactName: name);
  void setPaymentDate(String d) => state = state.copyWith(paymentDate: d);
  void setPaymentMode(String m) => state = state.copyWith(paymentMode: m);
  void setReferenceNumber(String r) =>
      state = state.copyWith(referenceNumber: r);
  void setDescription(String d) => state = state.copyWith(description: d);

  void setAmount(double a) {
    state = state.copyWith(amount: a);
    _resuggest();
  }

  void setAvailableInvoices(List<OutstandingInvoice> invoices) {
    state = state.copyWith(availableInvoices: invoices);
    _resuggest();
  }

  void _resuggest() {
    if (state.amount <= 0 || state.availableInvoices.isEmpty) {
      state = state.copyWith(allocations: const [], unallocated: state.amount);
      return;
    }
    final r = _allocation.suggestAllocations(
      paymentAmount: state.amount,
      invoices: state.availableInvoices,
    );
    state = state.copyWith(allocations: r.allocations, unallocated: r.surplus);
  }

  void updateAllocation(int index, double amount) {
    if (index >= state.allocations.length) return;
    final allocations = [...state.allocations];
    allocations[index] = allocations[index].copyWith(amount: amount);
    state = state.copyWith(allocations: allocations);
    _recalcUnallocated();
  }

  void _recalcUnallocated() {
    final total = state.allocations.fold<double>(0, (s, a) => s + a.amount);
    state = state.copyWith(
      unallocated: (state.amount - total).clamp(0, double.infinity),
    );
  }

  Future<Payment?> create() async {
    state = state.copyWith(saving: true, error: null, clearError: true);
    final check = _validation.validateForCreate(
      contactId: state.contactId,
      paymentDate: state.paymentDate,
      paymentMode: state.paymentMode,
      amount: state.amount,
      allocations: state.allocations,
      availableInvoices: state.availableInvoices,
    );
    if (!check.$1) {
      state = state.copyWith(saving: false, error: check.$2);
      return null;
    }
    final payload = <String, dynamic>{
      'contact_id': state.contactId,
      'payment_date': state.paymentDate,
      'payment_mode': state.paymentMode,
      'amount': state.amount,
      if (state.referenceNumber != null)
        'reference_number': state.referenceNumber,
      if (state.description != null) 'description': state.description,
      'allocations': state.allocations.map((a) => a.toCreatePayload()).toList(),
    };
    final result = await _service.create(payload);
    state = state.copyWith(saving: false);
    if (result is Success<Payment>) return result.value;
    if (result is Failure<Payment>) {
      state = state.copyWith(error: result.error.message);
    }
    return null;
  }
}
