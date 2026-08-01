/// Purchase return list + returnable-bills providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/features/offline_repository_providers.dart';
import '../../vendor_bills/models/vendor_bill.dart';
import '../../vendor_bills/models/bill_status.dart';
import '../models/purchase_return.dart';
import '../models/purchase_return_status.dart';

final purchaseReturnListProvider =
    StreamProvider.autoDispose<List<PurchaseReturnListItem>>((ref) {
      final repo = ref.watch(returnsRepositoryProvider);
      return repo.watchPurchaseReturns().map((list) {
        return list.map((item) {
          return PurchaseReturnListItem(
            id: item.localId,
            returnNumber: item.localId.substring(0, 8).toUpperCase(),
            contactName: item.supplierName,
            total: item.totalPaise / 100.0,
            returnDate: item.returnDate,
            status: PurchaseReturnStatus.fromString(item.lifecycleStatus),
            createdAt: item.createdAt.toIso8601String(),
          );
        }).toList();
      });
    });

/// Bills eligible to be returned against — posted / unpaid / partially paid.
final returnableBillsProvider =
    StreamProvider.autoDispose<List<VendorBillListItem>>((ref) {
      final repo = ref.watch(purchasingRepositoryProvider);
      return repo.watchPurchaseInvoices().map((list) {
        return list
            .map((item) {
              return VendorBillListItem(
                id: item.localId,
                billNumber: item.invoiceNumber,
                issueDate: item.invoiceDate,
                status: BillStatus.fromString(item.lifecycleStatus),
                total: item.totalPaise / 100.0,
                amountPaid: 0,
                contactName: item.supplierName,
                createdAt: item.createdAt.toIso8601String(),
              );
            })
            .where(
              (b) =>
                  b.status == BillStatus.posted ||
                  b.status == BillStatus.unpaid ||
                  b.status == BillStatus.partiallyPaid ||
                  b.status == BillStatus.paid,
            )
            .toList();
      });
    });
