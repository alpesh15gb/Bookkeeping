import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/delivery_challan_provider.dart';
import 'package:flutter_client/views/shared/transaction_form_view.dart';

class DeliveryChallanFormView extends StatelessWidget {
  final Map<String, dynamic>? challan;

  const DeliveryChallanFormView({super.key, this.challan});

  @override
  Widget build(BuildContext context) {
    return TransactionFormView(
      editEntity: challan,
      config: TransactionConfig(
        title: 'Delivery Challan',
        contactLabel: 'Customer',
        contactType: 'CUSTOMER',
        numberLabel: 'Challan Number',
        numberKey: 'challan_number',
        isPurchase: false,
        hasReferenceNo: false,
        hasShippingAddress: false,
        hasLinkedInvoice: false,
        allowScanning: false,
        successMessage: challan != null ? 'Challan updated' : 'Challan created',
        onSave: (ctx, payload) async {
          final provider = ctx.read<DeliveryChallanProvider>();
          final success = challan != null
              ? await provider.updateChallan(challan!['id'], payload)
              : await provider.createChallan(payload);
          if (!success && ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text(provider.errorMessage ?? 'Failed to save challan'),
              backgroundColor: AppColors.error,
            ));
          }
          return success;
        },
      ),
    );
  }
}
