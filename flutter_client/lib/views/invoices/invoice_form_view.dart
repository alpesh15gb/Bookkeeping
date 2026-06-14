import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/invoice_provider.dart';
import 'package:flutter_client/models/invoice.dart';
import 'package:flutter_client/views/shared/transaction_form_view.dart';
import 'package:flutter_client/views/shared/app_components.dart';

class InvoiceFormView extends StatelessWidget {
  final InvoiceModel? editInvoice;
  final Map<String, dynamic>? initialData;

  const InvoiceFormView({super.key, this.editInvoice, this.initialData});

  @override
  Widget build(BuildContext context) {
    return TransactionFormView(
      editEntity: editInvoice,
      initialData: initialData,
      config: TransactionConfig(
        title: 'Create Invoice',
        contactLabel: 'Customer',
        contactType: 'CUSTOMER',
        numberLabel: 'Invoice Number',
        numberKey: 'invoice_number',
        isPurchase: false,
        hasReferenceNo: true,
        hasShippingAddress: true,
        hasLinkedInvoice: false,
        allowScanning: false,
        hasCurrencySelector: true,
        hasTdsTcs: true,
        defaultCurrency: editInvoice?.currency ?? 'INR',
        defaultExchangeRate: editInvoice?.exchangeRate ?? 1.0,
        successMessage: editInvoice != null ? 'Invoice updated' : 'Invoice created',
        paymentTermsOptions: const [
          'Due on Receipt',
          'Net 15',
          'Net 30',
          'Net 45',
          'Net 60',
          'Net 90',
        ],
        onSave: (ctx, payload) async {
          final provider = ctx.read<InvoiceProvider>();
          final success = editInvoice != null
              ? await provider.updateInvoice(editInvoice!.id, payload)
              : await provider.createInvoice(payload);
          if (!success && ctx.mounted) {
            AppToast.error(ctx, provider.errorMessage ?? 'Failed to save invoice');
          }
          return success;
        },
        onPreview: (ctx, payload) async {
          final preview = await ctx.read<InvoiceProvider>().previewInvoice(payload);
          if (preview == null) return null;
          return {
            'subtotal': preview.subtotal,
            'discount_total': preview.discountTotal,
            'cgst_amount': preview.cgstAmount,
            'sgst_amount': preview.sgstAmount,
            'igst_amount': preview.igstAmount,
            'utgst_amount': preview.utgstAmount,
            'cess_amount': preview.cessAmount,
            'round_off': preview.roundOff,
            'total': preview.total,
          };
        },
      ),
    );
  }
}
