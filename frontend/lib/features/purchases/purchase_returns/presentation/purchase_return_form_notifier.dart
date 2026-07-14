/// Purchase return form notifier — loads a posted bill's lines and records
/// returned quantities. Reuses bill + return services (no new API).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../../vendor_bills/models/vendor_bill.dart';
import '../../vendor_bills/services/vendor_bill_service.dart';
import '../models/purchase_return.dart';
import '../models/purchase_return_line.dart';
import '../services/purchase_return_service.dart';
import 'purchase_return_form_state.dart';

class PurchaseReturnFormNotifier
    extends StateNotifier<PurchaseReturnFormState> {
  PurchaseReturnFormNotifier(this._returnService, this._billService)
    : super(const PurchaseReturnFormState());

  final PurchaseReturnService _returnService;
  final VendorBillService _billService;

  void setReturnDate(String d) => state = state.copyWith(returnDate: d);
  void setNotes(String n) => state = state.copyWith(notes: n);

  /// Load a bill and seed return lines (default returned qty = 0).
  Future<void> selectBill(String billId) async {
    state = state.copyWith(loadingBill: true, clearError: true);
    final res = await _billService.get(billId);
    switch (res) {
      case Success<VendorBill>(:final value):
        final lines = value.lines
            .map(
              (l) => PurchaseReturnLine(
                billLineId: l.id,
                productId: l.productId,
                productName: l.productName ?? l.description,
                quantityReturned: 0,
                maximumQuantity: l.quantity,
                rate: l.rate,
                hsnSac: l.hsnSac,
                gstRate: l.gstRate,
                reason: l.description,
              ),
            )
            .toList();
        state = state.copyWith(
          billId: value.id,
          billNumber: value.billNumber,
          contactName: value.contactName ?? '',
          contactId: value.contactId,
          posStateCode: value.posStateCode,
          lines: lines,
          loadingBill: false,
        );
      case Failure(:final error):
        state = state.copyWith(loadingBill: false, error: error.message);
      default:
        state = state.copyWith(loadingBill: false);
    }
  }

  void setLineQuantity(int index, double qty) {
    final lines = [...state.lines];
    lines[index] = lines[index].copyWith(quantityReturned: qty);
    state = state.copyWith(lines: lines);
  }

  void setLineReason(int index, String reason) {
    final lines = [...state.lines];
    lines[index] = lines[index].copyWith(reason: reason);
    state = state.copyWith(lines: lines);
  }

  /// Inline validation (no dedicated backend validation service exists).
  String? _validate() {
    if (!state.hasBill) return 'A source bill is required';
    if (state.returnDate.isEmpty) return 'Return date is required';
    final returned = state.lines.where((l) => l.quantityReturned > 0).toList();
    if (returned.isEmpty) return 'Enter a return quantity on at least one line';
    for (final l in returned) {
      if (l.quantityReturned > l.maximumQuantity) {
        return 'Return quantity cannot exceed the billed quantity';
      }
    }
    return null;
  }

  Future<PurchaseReturn?> create() async {
    state = state.copyWith(saving: true, clearError: true);
    final err = _validate();
    if (err != null) {
      state = state.copyWith(saving: false, error: err);
      return null;
    }
    final ret = PurchaseReturn(
      id: '',
      billId: state.billId,
      billNumber: state.billNumber,
      contactId: state.contactId,
      posStateCode: state.posStateCode,
      returnDate: state.returnDate,
      notes: state.notes,
      lines: state.lines.where((l) => l.quantityReturned > 0).toList(),
    );
    final result = await _returnService.create(ret);
    state = state.copyWith(saving: false);
    if (result is Success<PurchaseReturn>) return result.value;
    if (result is Failure<PurchaseReturn>) {
      state = state.copyWith(error: result.error.message);
    }
    return null;
  }
}

final purchaseReturnFormProvider =
    StateNotifierProvider.autoDispose<
      PurchaseReturnFormNotifier,
      PurchaseReturnFormState
    >((ref) {
      return PurchaseReturnFormNotifier(
        ref.watch(purchaseReturnServiceProvider),
        ref.watch(vendorBillServiceProvider),
      );
    });
