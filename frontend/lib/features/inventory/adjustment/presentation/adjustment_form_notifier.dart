/// Inventory adjustment form notifier — create-then-confirm workflow.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../services/adjustment_service.dart';
import 'adjustment_form_state.dart';

class AdjustmentFormNotifier extends StateNotifier<AdjustmentFormState> {
  AdjustmentFormNotifier(this._service)
    : super(
        const AdjustmentFormState(
          lines: [AdjustmentLine(productId: '', quantityChange: 0)],
        ),
      );

  final AdjustmentService _service;

  void setNumber(String v) => state = state.copyWith(adjustmentNumber: v);
  void setDate(String d) => state = state.copyWith(adjustmentDate: d);
  void setReason(String r) => state = state.copyWith(reason: r);

  void updateLine(int index, AdjustmentLine line) {
    final lines = [...state.lines]..[index] = line;
    state = state.copyWith(lines: lines);
  }

  void addLine() => state = state.copyWith(
    lines: [
      ...state.lines,
      const AdjustmentLine(productId: '', quantityChange: 0),
    ],
  );

  void removeLine(int index) {
    if (state.lines.length <= 1) return;
    state = state.copyWith(lines: [...state.lines]..removeAt(index));
  }

  String? _validate() {
    if (state.adjustmentNumber.trim().isEmpty) {
      return 'Adjustment number is required';
    }
    if (state.adjustmentDate.isEmpty) return 'Adjustment date is required';
    final valid = state.lines
        .where((l) => l.productId.isNotEmpty && l.quantityChange != 0)
        .toList();
    if (valid.isEmpty) {
      return 'Add at least one product with a non-zero quantity change';
    }
    return null;
  }

  Future<InventoryAdjustment?> create() async {
    state = state.copyWith(saving: true, clearError: true);
    final err = _validate();
    if (err != null) {
      state = state.copyWith(saving: false, error: err);
      return null;
    }
    final result = await _service.create(
      adjustmentNumber: state.adjustmentNumber.trim(),
      adjustmentDate: state.adjustmentDate,
      reason: state.reason,
      lines: state.lines
          .where((l) => l.productId.isNotEmpty && l.quantityChange != 0)
          .toList(),
    );
    state = state.copyWith(saving: false);
    if (result is Success<InventoryAdjustment>) return result.value;
    if (result is Failure<InventoryAdjustment>) {
      state = state.copyWith(error: result.error.message);
    }
    return null;
  }
}

final adjustmentFormProvider =
    StateNotifierProvider.autoDispose<
      AdjustmentFormNotifier,
      AdjustmentFormState
    >((ref) {
      return AdjustmentFormNotifier(ref.watch(adjustmentServiceProvider));
    });
