import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/shared/transaction_form_view.dart';

class EstimateFormView extends StatelessWidget {
  final dynamic editEstimate;

  const EstimateFormView({super.key, this.editEstimate});

  @override
  Widget build(BuildContext context) {
    return TransactionFormView(
      editEntity: editEstimate,
      config: TransactionConfig(
        title: 'Estimate / Proforma Invoice',
        contactLabel: 'Customer',
        contactType: 'CUSTOMER',
        numberLabel: 'Estimate Number',
        numberKey: 'proforma_number',
        isPurchase: false,
        hasReferenceNo: false,
        hasShippingAddress: false,
        hasLinkedInvoice: false,
        allowScanning: false,
        successMessage: editEstimate != null ? 'Estimate updated' : 'Estimate created',
        onSave: (ctx, payload) async {
          final provider = ctx.read<DocumentProvider>();
          final success = editEstimate != null
              ? await provider.updateEstimate(editEstimate!['id'], payload)
              : await provider.createEstimate(payload);
          if (!success && ctx.mounted) {
            AppToast.error(ctx, provider.errorMessage ?? 'Failed to save estimate');
          }
          return success;
        },
        onPreview: (ctx, payload) async {
          final result = await ctx.read<DocumentProvider>().previewEstimate(payload);
          if (result == null) return null;
          return {
            'subtotal': result['subtotal'],
            'discount_total': result['discount_total'],
            'cgst_amount': result['cgst_amount'],
            'sgst_amount': result['sgst_amount'],
            'igst_amount': result['igst_amount'],
            'utgst_amount': result['utgst_amount'],
            'cess_amount': result['cess_amount'],
            'round_off': result['round_off'],
            'total': result['total'],
          };
        },
      ),
    );
  }
}
