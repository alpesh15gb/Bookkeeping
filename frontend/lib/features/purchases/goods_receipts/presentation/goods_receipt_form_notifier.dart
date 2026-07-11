/// Goods receipt form notifier — loads a confirmed PO's outstanding lines and
/// records received quantities. Reuses existing PO + GRN services (no new API).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../../purchase_orders/models/purchase_order.dart';
import '../../purchase_orders/services/purchase_order_service.dart';
import '../models/goods_receipt.dart';
import '../models/goods_receipt_line.dart';
import '../services/goods_receipt_service.dart';
import '../services/goods_receipt_validation_service.dart';
import 'goods_receipt_form_state.dart';

class GoodsReceiptFormNotifier extends StateNotifier<GoodsReceiptFormState> {
  GoodsReceiptFormNotifier(this._grService, this._poService, this._validation)
    : super(const GoodsReceiptFormState());

  final GoodsReceiptService _grService;
  final PurchaseOrderService _poService;
  final GoodsReceiptValidationService _validation;

  void setReceiptDate(String d) => state = state.copyWith(receiptDate: d);
  void setNotes(String n) => state = state.copyWith(notes: n);

  /// Load a confirmed PO and seed receipt lines from its outstanding quantities.
  Future<void> selectPurchaseOrder(String poId) async {
    state = state.copyWith(loadingPo: true, clearError: true);
    final res = await _poService.get(poId);
    switch (res) {
      case Success<PurchaseOrder>(:final value):
        final lines = value.lines
            .map(
              (l) => GoodsReceiptLine(
                purchaseOrderLineId: l.id ?? '',
                productId: l.productId,
                productName: l.productName ?? l.description,
                quantityOrdered: l.quantity,
                // Default to the outstanding quantity (ordered minus already received).
                quantityReceived: (l.quantity - l.quantityReceived)
                    .clamp(0, double.infinity)
                    .toDouble(),
              ),
            )
            .toList();
        state = state.copyWith(
          purchaseOrderId: value.id,
          poNumber: value.poNumber,
          contactName: value.contactName ?? '',
          lines: lines,
          loadingPo: false,
        );
      case Failure(:final error):
        state = state.copyWith(loadingPo: false, error: error.message);
      default:
        state = state.copyWith(loadingPo: false);
    }
  }

  void setLineQuantity(int index, double qty) {
    final lines = [...state.lines];
    lines[index] = lines[index].copyWith(quantityReceived: qty);
    state = state.copyWith(lines: lines);
  }

  void setLineWarehouse(int index, String? warehouseId, String? warehouseName) {
    final lines = [...state.lines];
    lines[index] = lines[index].copyWith(
      warehouseId: warehouseId,
      warehouseName: warehouseName,
    );
    state = state.copyWith(lines: lines);
  }

  Future<GoodsReceipt?> create() async {
    state = state.copyWith(saving: true, clearError: true);
    final gr = GoodsReceipt(
      id: '',
      purchaseOrderId: state.purchaseOrderId,
      poNumber: state.poNumber,
      receiptDate: state.receiptDate,
      notes: state.notes,
      lines: state.lines.where((l) => l.quantityReceived > 0).toList(),
    );
    final err =
        _validation.validateForConfirm(gr) ??
        _validation.validateHasReceivedQuantity(gr);
    if (err != null) {
      state = state.copyWith(saving: false, error: err);
      return null;
    }
    final result = await _grService.create(gr);
    state = state.copyWith(saving: false);
    if (result is Success<GoodsReceipt>) return result.value;
    if (result is Failure<GoodsReceipt>) {
      state = state.copyWith(error: result.error.message);
    }
    return null;
  }
}

final goodsReceiptFormProvider =
    StateNotifierProvider.autoDispose<
      GoodsReceiptFormNotifier,
      GoodsReceiptFormState
    >((ref) {
      return GoodsReceiptFormNotifier(
        ref.watch(goodsReceiptServiceProvider),
        ref.watch(purchaseOrderServiceProvider),
        const GoodsReceiptValidationService(),
      );
    });
