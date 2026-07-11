/// Purchase order form notifier — create-only (no backend update endpoint).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_line.dart';
import '../services/purchase_order_service.dart';
import '../services/purchase_order_calculation_service.dart';
import '../services/purchase_order_validation_service.dart';
import 'purchase_order_form_state.dart';

class PurchaseOrderFormNotifier extends StateNotifier<PurchaseOrderFormState> {
  PurchaseOrderFormNotifier(this._service, this._calc, this._validation)
    : super(
        const PurchaseOrderFormState(
          lines: [PurchaseOrderLine(productId: '', hsnSac: '', gstRate: 18)],
        ),
      );

  final PurchaseOrderService _service;
  final PurchaseOrderCalculationService _calc;
  final PurchaseOrderValidationService _validation;

  void setPoNumber(String v) => state = state.copyWith(poNumber: v);
  void setContact(String id, String name) =>
      state = state.copyWith(contactId: id, contactName: name);
  void setOrderDate(String d) => state = state.copyWith(orderDate: d);
  void setDueDate(String d) => state = state.copyWith(dueDate: d);
  void setPosStateCode(String c) => state = state.copyWith(posStateCode: c);

  void updateLine(int index, PurchaseOrderLine line) {
    final lines = [...state.lines]..[index] = line;
    _recalc(state.copyWith(lines: lines));
  }

  void addLine() {
    _recalc(
      state.copyWith(
        lines: [
          ...state.lines,
          const PurchaseOrderLine(productId: '', hsnSac: '', gstRate: 18),
        ],
      ),
    );
  }

  void removeLine(int index) {
    if (state.lines.length <= 1) return;
    _recalc(state.copyWith(lines: [...state.lines]..removeAt(index)));
  }

  void _recalc(PurchaseOrderFormState s) {
    final r = _calc.calculateAll(lines: s.lines);
    state = s.copyWith(
      lines: r.lines,
      subtotal: r.subtotal,
      discountTotal: r.discountTotal,
      totalTax: r.totalTax,
      total: r.total,
    );
  }

  Future<PurchaseOrder?> create() async {
    state = state.copyWith(saving: true, clearError: true);
    final po = PurchaseOrder(
      id: '',
      poNumber: state.poNumber.trim(),
      contactId: state.contactId ?? '',
      orderDate: state.orderDate,
      dueDate: state.dueDate,
      posStateCode: state.posStateCode,
      lines: state.lines.where((l) => l.productId.isNotEmpty).toList(),
    );
    final err = _validation.validateForSubmit(po);
    if (err != null) {
      state = state.copyWith(saving: false, error: err);
      return null;
    }
    final result = await _service.create(po);
    state = state.copyWith(saving: false);
    if (result is Success<PurchaseOrder>) return result.value;
    if (result is Failure<PurchaseOrder>) {
      state = state.copyWith(error: result.error.message);
    }
    return null;
  }
}

final purchaseOrderFormProvider =
    StateNotifierProvider.autoDispose<
      PurchaseOrderFormNotifier,
      PurchaseOrderFormState
    >((ref) {
      return PurchaseOrderFormNotifier(
        ref.watch(purchaseOrderServiceProvider),
        const PurchaseOrderCalculationService(),
        const PurchaseOrderValidationService(),
      );
    });
