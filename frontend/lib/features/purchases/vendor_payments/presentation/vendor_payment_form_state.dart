/// Vendor payment form state — record a payment and allocate across bills.
library;

import '../models/outstanding_bill.dart';
import '../models/vendor_payment.dart';
import '../models/vendor_payment_enums.dart';

class VendorPaymentFormState {
  const VendorPaymentFormState({
    this.paymentNumber = '',
    this.contactId,
    this.contactName = '',
    this.paymentDate = '',
    this.paymentMode = PaymentMode.bank,
    this.amount = 0,
    this.referenceNumber,
    this.bills = const [],
    this.allocations = const {},
    this.loadingBills = false,
    this.saving = false,
    this.error,
  });

  final String paymentNumber;
  final String? contactId;
  final String contactName;
  final String paymentDate;
  final PaymentMode paymentMode;
  final double amount;
  final String? referenceNumber;
  final List<OutstandingBill> bills;

  /// billId -> allocated amount.
  final Map<String, double> allocations;
  final bool loadingBills;
  final bool saving;
  final String? error;

  bool get hasVendor => (contactId ?? '').isNotEmpty;
  double get totalAllocated =>
      allocations.values.fold<double>(0, (s, a) => s + a);
  double get unallocated => (amount - totalAllocated).clamp(0, double.infinity);

  List<PaymentAllocation> get allocationList => allocations.entries
      .where((e) => e.value > 0)
      .map(
        (e) => PaymentAllocation(
          billId: e.key,
          billNumber: bills
              .firstWhere(
                (b) => b.id == e.key,
                orElse: () => const OutstandingBill(id: ''),
              )
              .billNumber,
          amount: e.value,
        ),
      )
      .toList();

  VendorPaymentFormState copyWith({
    String? paymentNumber,
    String? contactId,
    String? contactName,
    String? paymentDate,
    PaymentMode? paymentMode,
    double? amount,
    String? referenceNumber,
    List<OutstandingBill>? bills,
    Map<String, double>? allocations,
    bool? loadingBills,
    bool? saving,
    String? error,
    bool clearError = false,
  }) => VendorPaymentFormState(
    paymentNumber: paymentNumber ?? this.paymentNumber,
    contactId: contactId ?? this.contactId,
    contactName: contactName ?? this.contactName,
    paymentDate: paymentDate ?? this.paymentDate,
    paymentMode: paymentMode ?? this.paymentMode,
    amount: amount ?? this.amount,
    referenceNumber: referenceNumber ?? this.referenceNumber,
    bills: bills ?? this.bills,
    allocations: allocations ?? this.allocations,
    loadingBills: loadingBills ?? this.loadingBills,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
  );
}
