/// Transfer form notifier — create inter-warehouse stock transfers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/features/inventory/warehouse/services/warehouse_service.dart';
import '../services/transfer_service.dart';
import 'transfer_form_state.dart';

class TransferFormNotifier extends StateNotifier<TransferFormState> {
  TransferFormNotifier(this._service, this._warehouseService)
    : super(const TransferFormState());

  final TransferService _service;
  final WarehouseService _warehouseService;

  Future<void> loadWarehouses() async {
    final res = await _warehouseService.list();
    if (res is Success<List<Warehouse>>) {
      state = state.copyWith(warehouses: res.value);
    }
  }

  void setNumber(String v) => state = state.copyWith(transferNumber: v);
  void setDate(String d) => state = state.copyWith(transferDate: d);
  void setFromWarehouse(String? id) =>
      state = state.copyWith(fromWarehouseId: id ?? '');
  void setToWarehouse(String? id) =>
      state = state.copyWith(toWarehouseId: id ?? '');

  void addLine() => state = state.copyWith(
    lines: [
      ...state.lines,
      const TransferLine(productId: '', quantity: 0),
    ],
  );

  void removeLine(int index) {
    if (state.lines.length <= 1) return;
    state = state.copyWith(lines: [...state.lines]..removeAt(index));
  }

  void updateLine(int index, TransferLine line) {
    final lines = [...state.lines]..[index] = line;
    state = state.copyWith(lines: lines);
  }

  String? _validate() {
    if (state.transferNumber.trim().isEmpty)
      return 'Transfer number is required';
    if (state.transferDate.isEmpty) return 'Transfer date is required';
    if (!state.hasValidRoute)
      return 'Select different source and destination warehouses';
    final valid = state.lines
        .where((l) => l.productId.isNotEmpty && l.quantity > 0)
        .toList();
    if (valid.isEmpty) return 'Add at least one product with quantity';
    return null;
  }

  Future<Transfer?> create() async {
    state = state.copyWith(saving: true, clearError: true);
    final err = _validate();
    if (err != null) {
      state = state.copyWith(saving: false, error: err);
      return null;
    }
    final payload = <String, dynamic>{
      'transfer_number': state.transferNumber.trim(),
      'transfer_date': state.transferDate,
      'from_warehouse_id': state.fromWarehouseId,
      'to_warehouse_id': state.toWarehouseId,
      'line_items': state.lines
          .where((l) => l.productId.isNotEmpty && l.quantity > 0)
          .map(
            (l) => {
              'product_id': l.productId,
              'product_name': l.productName,
              'quantity': l.quantity,
              'rate': l.rate,
            },
          )
          .toList(),
    };
    final result = await _service.create(payload);
    state = state.copyWith(saving: false);
    if (result is Success<Transfer>) return result.value;
    if (result is Failure<Transfer>) {
      state = state.copyWith(error: result.error.message);
    }
    return null;
  }
}

final transferFormProvider =
    StateNotifierProvider.autoDispose<TransferFormNotifier, TransferFormState>((
      ref,
    ) {
      return TransferFormNotifier(
        ref.watch(transferServiceProvider),
        ref.watch(warehouseServiceProvider),
      );
    });
