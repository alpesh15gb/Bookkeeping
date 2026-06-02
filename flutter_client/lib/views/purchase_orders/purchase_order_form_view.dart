import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/purchase_order_provider.dart';
import 'package:flutter_client/views/shared/transaction_form_view.dart';

class PurchaseOrderFormView extends StatelessWidget {
  final Map<String, dynamic>? editOrder;
  final String orderType;

  const PurchaseOrderFormView({super.key, this.editOrder, this.orderType = 'purchase'});

  @override
  Widget build(BuildContext context) {
    final isPurchase = orderType == 'purchase';
    final label = isPurchase ? 'Purchase Order' : 'Sales Order';

    return TransactionFormView(
      editEntity: editOrder,
      config: TransactionConfig(
        title: label,
        contactLabel: isPurchase ? 'Vendor' : 'Customer',
        contactType: isPurchase ? 'VENDOR' : 'CUSTOMER',
        numberLabel: isPurchase ? 'PO Number' : 'SO Number',
        numberKey: isPurchase ? 'po_number' : 'so_number',
        isPurchase: isPurchase,
        hasReferenceNo: false,
        hasShippingAddress: false,
        hasLinkedInvoice: false,
        allowScanning: false,
        successMessage: editOrder != null ? '$label updated' : '$label created',
        onSave: (ctx, payload) async {
          final provider = ctx.read<PurchaseOrderProvider>();
          final success = editOrder != null
              ? (isPurchase
                  ? await provider.updatePurchaseOrder(editOrder!['id'], payload)
                  : await provider.updateSalesOrder(editOrder!['id'], payload))
              : (isPurchase
                  ? await provider.createPurchaseOrder(payload)
                  : await provider.createSalesOrder(payload));
          if (!success && ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text(provider.errorMessage ?? 'Failed to save $label'),
              backgroundColor: AppColors.error,
            ));
          }
          return success;
        },
      ),
    );
  }
}
