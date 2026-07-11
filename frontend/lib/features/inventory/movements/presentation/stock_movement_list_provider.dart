/// Stock movements (ledger) list provider — read-only audit trail.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/features/inventory/stock/models/stock_models.dart';
import '../services/movement_service.dart';

class MovementQuery {
  const MovementQuery({this.referenceType});
  final MovementReferenceType? referenceType;

  @override
  bool operator ==(Object other) =>
      other is MovementQuery && other.referenceType == referenceType;
  @override
  int get hashCode => referenceType.hashCode;
}

final stockMovementsProvider = FutureProvider.autoDispose
    .family<List<StockMovement>, MovementQuery>((ref, query) async {
      final res = await ref
          .watch(movementServiceProvider)
          .getAllMovements(
            limit: 200,
            referenceType: query.referenceType?.value,
          );
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });
