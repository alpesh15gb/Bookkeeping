/// Payment receipt form state.
library;

import '../models/payment_models.dart';
import '../models/outstanding_invoice.dart';

class PaymentFormState {
  const PaymentFormState({
    this.contactId,
    this.contactName = '',
    this.paymentDate = '',
    this.paymentMode = 'BANK',
    this.amount = 0,
    this.referenceNumber,
    this.description,
    this.advanceSupplyType = 'GOODS',
    this.allocations = const [],
    this.availableInvoices = const [],
    this.unallocated = 0,
    this.saving = false,
    this.loadingInvoices = false,
    this.error,
  });

  final String? contactId;
  final String contactName;
  final String paymentDate;
  final String paymentMode;
  final double amount;
  final String? referenceNumber;
  final String? description;
  final String advanceSupplyType;
  final List<PaymentAllocation> allocations;
  final List<OutstandingInvoice> availableInvoices;
  final double unallocated;
  final bool saving;
  final bool loadingInvoices;
  final String? error;

  double get allocatedTotal =>
      allocations.fold<double>(0, (s, a) => s + a.amount);
  bool get isValid => contactId != null && paymentDate.isNotEmpty && amount > 0;

  PaymentFormState copyWith({
    String? contactId,
    String? contactName,
    String? paymentDate,
    String? paymentMode,
    double? amount,
    String? referenceNumber,
    String? description,
    String? advanceSupplyType,
    List<PaymentAllocation>? allocations,
    List<OutstandingInvoice>? availableInvoices,
    double? unallocated,
    bool? saving,
    bool? loadingInvoices,
    String? error,
    bool clearError = false,
  }) => PaymentFormState(
    contactId: contactId ?? this.contactId,
    contactName: contactName ?? this.contactName,
    paymentDate: paymentDate ?? this.paymentDate,
    paymentMode: paymentMode ?? this.paymentMode,
    amount: amount ?? this.amount,
    referenceNumber: referenceNumber ?? this.referenceNumber,
    description: description ?? this.description,
    advanceSupplyType: advanceSupplyType ?? this.advanceSupplyType,
    allocations: allocations ?? this.allocations,
    availableInvoices: availableInvoices ?? this.availableInvoices,
    unallocated: unallocated ?? this.unallocated,
    saving: saving ?? this.saving,
    loadingInvoices: loadingInvoices ?? this.loadingInvoices,
    error: clearError ? null : (error ?? this.error),
  );
}
