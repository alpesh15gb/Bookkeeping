/// Inventory adjustment form state.
library;

import '../services/adjustment_service.dart';

class AdjustmentFormState {
  const AdjustmentFormState({
    this.adjustmentNumber = '',
    this.adjustmentDate = '',
    this.reason,
    this.lines = const [],
    this.saving = false,
    this.error,
  });

  final String adjustmentNumber;
  final String adjustmentDate;
  final String? reason;
  final List<AdjustmentLine> lines;
  final bool saving;
  final String? error;

  int get increaseCount => lines.where((l) => l.quantityChange > 0).length;
  int get decreaseCount => lines.where((l) => l.quantityChange < 0).length;

  AdjustmentFormState copyWith({
    String? adjustmentNumber,
    String? adjustmentDate,
    String? reason,
    List<AdjustmentLine>? lines,
    bool? saving,
    String? error,
    bool clearError = false,
  }) => AdjustmentFormState(
    adjustmentNumber: adjustmentNumber ?? this.adjustmentNumber,
    adjustmentDate: adjustmentDate ?? this.adjustmentDate,
    reason: reason ?? this.reason,
    lines: lines ?? this.lines,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
  );
}
