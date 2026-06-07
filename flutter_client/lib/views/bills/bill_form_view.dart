import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/bill_provider.dart';
import 'package:flutter_client/models/bill.dart';
import 'package:flutter_client/views/shared/transaction_form_view.dart';
import 'package:flutter_client/views/shared/toast.dart';

class BillFormView extends StatelessWidget {
  final BillModel? editBill;

  const BillFormView({super.key, this.editBill});

  @override
  Widget build(BuildContext context) {
    return TransactionFormView(
      editEntity: editBill,
      config: TransactionConfig(
        title: 'Vendor Bill',
        contactLabel: 'Vendor',
        contactType: 'VENDOR',
        numberLabel: 'Bill Number',
        numberKey: 'bill_number',
        isPurchase: true,
        hasReferenceNo: false,
        hasShippingAddress: false,
        hasLinkedInvoice: false,
        allowScanning: true,
        successMessage: editBill != null ? 'Bill updated' : 'Bill created',
        onSave: (ctx, payload) async {
          final provider = ctx.read<BillProvider>();
          final success = editBill != null
              ? await provider.updateBill(editBill!.id, payload)
              : await provider.createBill(payload);
          if (!success && ctx.mounted) {
            AppToast.error(ctx, provider.errorMessage ?? 'Failed to save bill');
          }
          return success;
        },
        onPreview: (ctx, payload) async {
          final preview = await ctx.read<BillProvider>().previewBill(payload);
          if (preview == null) return null;
          return {
            'subtotal': preview.subtotal,
            'discount_total': preview.discountTotal,
            'cgst_amount': preview.cgstAmount,
            'sgst_amount': preview.sgstAmount,
            'igst_amount': preview.igstAmount,
            'round_off': preview.roundOff,
            'total': preview.total,
          };
        },
      ),
    );
  }
}
