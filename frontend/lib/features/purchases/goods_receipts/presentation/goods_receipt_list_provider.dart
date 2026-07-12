/// Goods receipt list + confirmed-PO providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../../purchase_orders/models/purchase_order.dart';
import '../../purchase_orders/models/purchase_order_status.dart';
import '../../purchase_orders/services/purchase_order_service.dart';
import '../models/goods_receipt.dart';
import '../services/goods_receipt_service.dart';

final goodsReceiptListProvider =
    FutureProvider.autoDispose<List<GoodsReceiptListItem>>((ref) async {
      final res = await ref.watch(goodsReceiptServiceProvider).list();
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });

/// Confirmed POs available to receive against.
final confirmedPurchaseOrdersProvider =
    FutureProvider.autoDispose<List<PurchaseOrderListItem>>((ref) async {
      final res = await ref
          .watch(purchaseOrderServiceProvider)
          .list(status: PurchaseOrderStatus.confirmed);
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });
