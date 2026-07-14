/// Purchase return list + returnable-bills providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../../vendor_bills/models/vendor_bill.dart';
import '../../vendor_bills/models/bill_status.dart';
import '../../vendor_bills/services/vendor_bill_service.dart';
import '../models/purchase_return.dart';
import '../services/purchase_return_service.dart';

final purchaseReturnListProvider =
    FutureProvider.autoDispose<List<PurchaseReturnListItem>>((ref) async {
      final res = await ref.watch(purchaseReturnServiceProvider).list();
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });

/// Bills eligible to be returned against — posted / unpaid / partially paid.
/// (Bill list has no server-side status filter, so we filter client-side.)
final returnableBillsProvider =
    FutureProvider.autoDispose<List<VendorBillListItem>>((ref) async {
      final res = await ref.watch(vendorBillServiceProvider).list(limit: 100);
      return switch (res) {
        Success(:final value) =>
          value
              .where(
                (b) =>
                    b.status == BillStatus.posted ||
                    b.status == BillStatus.unpaid ||
                    b.status == BillStatus.partiallyPaid ||
                    b.status == BillStatus.paid,
              )
              .toList(),
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });
