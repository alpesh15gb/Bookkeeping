import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/transaction_form_view.dart';

class CreditDebitNoteFormView extends StatelessWidget {
  final bool isCredit;
  final Map<String, dynamic>? editNote;

  const CreditDebitNoteFormView({
    super.key,
    required this.isCredit,
    this.editNote,
  });

  @override
  Widget build(BuildContext context) {
    final label = isCredit ? 'Credit Note' : 'Debit Note';

    return TransactionFormView(
      editEntity: editNote,
      config: TransactionConfig(
        title: label,
        contactLabel: isCredit ? 'Customer' : 'Vendor',
        contactType: isCredit ? 'CUSTOMER' : 'VENDOR',
        numberLabel: isCredit ? 'Credit Note Number' : 'Debit Note Number',
        numberKey: isCredit ? 'credit_note_number' : 'debit_note_number',
        isPurchase: !isCredit,
        hasReferenceNo: false,
        hasShippingAddress: false,
        hasLinkedInvoice: true,
        allowScanning: false,
        successMessage: '$label saved successfully',
        onSave: (ctx, payload) async {
          final provider = ctx.read<DocumentProvider>();
          bool success = isCredit
              ? await provider.createCreditNote(payload)
              : await provider.createDebitNote(payload);
          if (!success && ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text(provider.errorMessage ?? 'Failed to save note'),
              backgroundColor: AppColors.error,
            ));
          }
          return success;
        },
        onPreview: (ctx, payload) async {
          final provider = ctx.read<DocumentProvider>();
          return isCredit
              ? await provider.previewCreditNote(payload)
              : await provider.previewDebitNote(payload);
        },
      ),
    );
  }
}
