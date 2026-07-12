/// Inventory adjustment list + detail providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../services/adjustment_service.dart';

final adjustmentListProvider =
    FutureProvider.autoDispose<List<AdjustmentListItem>>((ref) async {
      final res = await ref.watch(adjustmentServiceProvider).list();
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });

final adjustmentDetailProvider = FutureProvider.autoDispose
    .family<InventoryAdjustment, String>((ref, id) async {
      final res = await ref.watch(adjustmentServiceProvider).get(id);
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });
