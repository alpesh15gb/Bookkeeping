/// Purchase order list provider — paginated list with optional status filter.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_status.dart';
import '../services/purchase_order_service.dart';

class PurchaseOrderListQuery {
  const PurchaseOrderListQuery({this.status});
  final PurchaseOrderStatus? status;

  @override
  bool operator ==(Object other) =>
      other is PurchaseOrderListQuery && other.status == status;
  @override
  int get hashCode => status.hashCode;
}

final purchaseOrderListProvider = FutureProvider.autoDispose
    .family<List<PurchaseOrderListItem>, PurchaseOrderListQuery>((
      ref,
      query,
    ) async {
      final res = await ref
          .watch(purchaseOrderServiceProvider)
          .list(status: query.status);
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });
