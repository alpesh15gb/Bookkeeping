/// Transfer form state — create inter-warehouse stock transfer.
library;

import 'package:apexbooks/features/inventory/transfers/services/transfer_service.dart';
import 'package:apexbooks/features/inventory/warehouse/services/warehouse_service.dart';

class TransferFormState {
  const TransferFormState({
    this.transferNumber = '',
    this.transferDate = '',
    this.fromWarehouseId = '',
    this.toWarehouseId = '',
    this.lines = const [],
    this.warehouses = const [],
    this.saving = false,
    this.error,
  });

  final String transferNumber;
  final String transferDate;
  final String fromWarehouseId;
  final String toWarehouseId;
  final List<TransferLine> lines;
  final List<Warehouse> warehouses;
  final bool saving;
  final String? error;

  bool get hasValidRoute =>
      fromWarehouseId.isNotEmpty &&
      toWarehouseId.isNotEmpty &&
      fromWarehouseId != toWarehouseId;

  TransferFormState copyWith({
    String? transferNumber,
    String? transferDate,
    String? fromWarehouseId,
    String? toWarehouseId,
    List<TransferLine>? lines,
    List<Warehouse>? warehouses,
    bool? saving,
    String? error,
    bool clearError = false,
  }) => TransferFormState(
    transferNumber: transferNumber ?? this.transferNumber,
    transferDate: transferDate ?? this.transferDate,
    fromWarehouseId: fromWarehouseId ?? this.fromWarehouseId,
    toWarehouseId: toWarehouseId ?? this.toWarehouseId,
    lines: lines ?? this.lines,
    warehouses: warehouses ?? this.warehouses,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
  );
}
