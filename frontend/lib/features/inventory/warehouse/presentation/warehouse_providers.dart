/// Shared warehouse providers — reused by goods receipts, transfers, and the
/// warehouse module. Backed by the existing [WarehouseService].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../services/warehouse_service.dart';

final warehouseListProvider = FutureProvider.autoDispose<List<Warehouse>>((
  ref,
) async {
  final res = await ref.watch(warehouseServiceProvider).list();
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});
