/// Purchase return form notifier — loads a posted bill's lines and records
/// returned quantities. Reuses bill + return services (no new API).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/features/offline_repository_providers.dart';
import 'package:apexbooks/features/purchasing/domain/repositories/purchasing_repository.dart';
import 'package:apexbooks/features/returns/domain/repositories/returns_repository.dart';
import 'package:apexbooks/features/returns/domain/commands/returns_commands.dart';
import '../models/purchase_return.dart';
import '../models/purchase_return_line.dart';
import 'purchase_return_form_state.dart';

class PurchaseReturnFormNotifier
    extends StateNotifier<PurchaseReturnFormState> {
  PurchaseReturnFormNotifier(this._returnsRepository, this._purchasingRepository)
    : super(const PurchaseReturnFormState());

  final ReturnsRepository _returnsRepository;
  final PurchasingRepository _purchasingRepository;

  void setReturnDate(String d) => state = state.copyWith(returnDate: d);
  void setNotes(String n) => state = state.copyWith(notes: n);

  /// Load a bill and seed return lines.
  Future<void> selectBill(String billId) async {
    state = state.copyWith(loadingBill: true, clearError: true);
    try {
      final pi = await _purchasingRepository.getPurchaseInvoice(billId);
      if (pi == null) {
        state = state.copyWith(loadingBill: false, error: 'Bill not found locally');
        return;
      }
      final lines = pi.lines
          .map(
            (l) => PurchaseReturnLine(
              billLineId: l.localId,
              productId: '',
              productName: l.productName,
              quantityReturned: 0,
              maximumQuantity: double.tryParse(l.quantity) ?? 0,
              rate: l.unitPricePaise / 100.0,
              hsnSac: '',
              gstRate: 0,
              reason: l.description,
            ),
          )
          .toList();
      state = state.copyWith(
        billId: pi.localId,
        billNumber: pi.invoiceNumber,
        contactName: pi.supplierName,
        contactId: pi.supplierId,
        posStateCode: '',
        lines: lines,
        loadingBill: false,
      );
    } catch (e) {
      state = state.copyWith(loadingBill: false, error: e.toString());
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

  /// Inline validation.
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

    final linesToReturn = state.lines.where((l) => l.quantityReturned > 0).toList();
    final double totalAmt = linesToReturn.fold<double>(0, (s, l) => s + l.quantityReturned * l.rate);

    try {
      final pr = await _returnsRepository.postPurchaseReturn(
        PostPurchaseReturnCommand(
          companyId: '',
          returnDate: state.returnDate,
          supplierId: state.contactId,
          supplierName: state.contactName,
          sourceReceiptLocalId: state.billId, // Passes billId
          referenceNumber: state.billNumber,
          description: state.notes,
          totalPaise: (totalAmt * 100).round(),
          lines: linesToReturn.map((l) {
            return PurchaseReturnLineCommand(
              sourceReceiptLineLocalId: l.billLineId ?? '',
              productName: l.productName ?? '',
              unit: 'PCS',
              quantity: l.quantityReturned.toString(),
              unitCostPaise: (l.rate * 100).round(),
              totalPaise: (l.quantityReturned * l.rate * 100).round(),
            );
          }).toList(),
        ),
      );
      state = state.copyWith(saving: false);
      return PurchaseReturn(
        id: pr.localId,
        billId: pr.sourceReceiptLocalId ?? '',
        billNumber: pr.referenceNumber ?? '',
        contactId: pr.supplierId,
        returnDate: pr.returnDate,
        total: pr.totalPaise / 100.0,
      );
    } catch (e) {
      state = state.copyWith(saving: false, error: e.toString());
      return null;
    }
  }
}

final purchaseReturnFormProvider =
    StateNotifierProvider.autoDispose<
      PurchaseReturnFormNotifier,
      PurchaseReturnFormState
    >((ref) {
      return PurchaseReturnFormNotifier(
        ref.watch(returnsRepositoryProvider),
        ref.watch(purchasingRepositoryProvider),
      );
    });
