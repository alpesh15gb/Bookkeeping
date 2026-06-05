import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/credit_notes/credit_debit_note_form_view.dart';

import 'package:flutter_client/core/print_share_helper.dart';
import 'package:flutter_client/views/shared/toast.dart';

class CreditDebitNoteDetailView extends StatefulWidget {
  final String noteId;
  final bool isCredit;

  const CreditDebitNoteDetailView({
    super.key,
    required this.noteId,
    required this.isCredit,
  });

  @override
  State<CreditDebitNoteDetailView> createState() => _CreditDebitNoteDetailViewState();
}

class _CreditDebitNoteDetailViewState extends State<CreditDebitNoteDetailView> {
  Map<String, dynamic>? _note;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  void _fetchDetail() async {
    final provider = context.read<DocumentProvider>();
    final detail = widget.isCredit
        ? await provider.fetchCreditNoteDetail(widget.noteId)
        : await provider.fetchDebitNoteDetail(widget.noteId);

    if (mounted) {
      setState(() {
        _note = detail;
        _isLoading = false;
      });
    }
  }

  void _finalizeNote() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Finalize Note?',
      message: 'This will lock the note and generate ledger entries. You cannot edit it after finalizing.',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<DocumentProvider>();
      final success = widget.isCredit
          ? await provider.finalizeCreditNote(widget.noteId)
          : await provider.finalizeDebitNote(widget.noteId);

      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _fetchDetail();
        } else {
          AppToast.error(context, provider.errorMessage ?? 'Failed to finalize');
        }
      }
    }
  }

  void _cancelNote() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel Note?',
      message: 'Are you sure you want to cancel this note? This will reverse ledger entries.',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<DocumentProvider>();
      final success = widget.isCredit
          ? await provider.cancelCreditNote(widget.noteId)
          : await provider.cancelDebitNote(widget.noteId);

      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _fetchDetail();
        } else {
          AppToast.error(context, provider.errorMessage ?? 'Failed to cancel');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: LoadingState(message: 'Loading note details...'));
    if (_note == null) return const Scaffold(body: ErrorState(message: 'Note details not found.'));

    final isMobile = AdaptiveLayout.isMobile(context);
    final number = widget.isCredit ? _note!['credit_note_number'] : _note!['debit_note_number'];
    final status = _note!['status'] ?? 'DRAFT';
    final lines = _note!['lines'] is List ? _note!['lines'] as List : [];

    final subtotal = double.tryParse((_note!['subtotal'] ?? 0).toString()) ?? 0.0;
    final total = double.tryParse((_note!['total'] ?? 0).toString()) ?? 0.0;
    final cgst = double.tryParse((_note!['cgst_amount'] ?? 0).toString()) ?? 0.0;
    final sgst = double.tryParse((_note!['sgst_amount'] ?? 0).toString()) ?? 0.0;
    final igst = double.tryParse((_note!['igst_amount'] ?? 0).toString()) ?? 0.0;
    final cess = double.tryParse((_note!['cess_amount'] ?? 0).toString()) ?? 0.0;
    final roundOff = double.tryParse((_note!['round_off'] ?? 0).toString()) ?? 0.0;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(number ?? 'Note Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              PrintShareHelper.showShareSheet(
                context,
                docLabel: widget.isCredit ? 'Credit Note' : 'Debit Note',
                docNumber: number ?? 'N/A',
                docType: widget.isCredit ? 'invoices/credit-notes' : 'invoices/debit-notes',
                docId: widget.noteId,
              );
            },
            tooltip: 'Share / Export',
          ),
          if (status == 'DRAFT')
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreditDebitNoteFormView(isCredit: widget.isCredit, editNote: _note),
                  ),
                ).then((updated) {
                  if (updated == true) _fetchDetail();
                });
              },
              tooltip: 'Edit Note',
            ),
          const SizedBox(width: 8),
          StatusBadge(label: status),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Card
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.brandNavy,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: const Icon(
                          Icons.compare_arrows_rounded,
                          size: 20,
                          color: AppColors.goldAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.isCredit ? 'CREDIT NOTE' : 'DEBIT NOTE', style: AppTextStyles.labelSmall),
                            Text(
                              number ?? 'N/A',
                              style: AppTextStyles.h2,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  InfoRow(label: 'Linked Invoice', value: _note!['invoice_number'] ?? 'Unlinked'),
                  InfoRow(label: 'Issue Date', value: _note!['issue_date'] ?? 'N/A'),
                  InfoRow(label: 'Reason', value: _note!['reason'] ?? 'N/A'),
                  if (_note!['contact_name'] != null)
                    InfoRow(label: 'Customer/Vendor', value: _note!['contact_name']),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Line Items Card
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'ITEMS'),
                  if (lines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      child: Text('No items', style: AppTextStyles.bodySmall),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: lines.length,
                      separatorBuilder: (context, _) => const Divider(),
                      itemBuilder: (context, i) {
                        final line = lines[i];
                        final qty = double.tryParse((line['quantity'] ?? 0).toString()) ?? 0.0;
                        final rate = double.tryParse((line['rate'] ?? 0).toString()) ?? 0.0;
                        final amt = double.tryParse((line['subtotal'] ?? 0).toString()) ?? (qty * rate);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      line['product_name'] ?? 'Product',
                                      style: AppTextStyles.bodyMedium,
                                    ),
                                    const SizedBox(height: AppSpacing.xxs),
                                    Text(
                                      'Qty: $qty × ₹${rate.toStringAsFixed(2)}',
                                      style: AppTextStyles.caption,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '₹${amt.toStringAsFixed(2)}',
                                style: AppTextStyles.numeric,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Summary Card
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'TAX & TOTAL SUMMARY'),
                  SummaryRow(label: 'Subtotal', value: '₹${subtotal.toStringAsFixed(2)}'),
                  SummaryRow(label: 'CGST', value: '₹${cgst.toStringAsFixed(2)}'),
                  SummaryRow(label: 'SGST', value: '₹${sgst.toStringAsFixed(2)}'),
                  if (igst > 0) SummaryRow(label: 'IGST', value: '₹${igst.toStringAsFixed(2)}'),
                  if (cess > 0) SummaryRow(label: 'Cess', value: '₹${cess.toStringAsFixed(2)}'),
                  SummaryRow(label: 'Round Off', value: '₹${roundOff.toStringAsFixed(2)}'),
                  const Divider(),
                  SummaryRow(
                    label: 'Total',
                    value: '₹${total.toStringAsFixed(2)}',
                    isBold: true,
                    valueColor: AppColors.brandNavy,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (status == 'DRAFT') ...[
              ActionButton(
                label: 'Finalize & Post',
                icon: Icons.lock_outline,
                tier: ActionTier.warning,
                onPressed: _finalizeNote,
              ),
              const SizedBox(height: 12),
              ActionButton(
                label: 'Delete Draft',
                icon: Icons.delete_outline,
                tier: ActionTier.dangerous,
                onPressed: _deleteNote,
              ),
            ],
            if (status == 'POSTED') ...[
              ActionButton(
                label: 'Cancel Note',
                icon: Icons.cancel_outlined,
                tier: ActionTier.dangerous,
                onPressed: _cancelNote,
              ),
            ],
            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }

  void _deleteNote() async {
    final noteType = widget.isCredit ? 'Credit Note' : 'Debit Note';
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Delete Draft $noteType?',
      message: 'Are you sure you want to permanently delete this draft $noteType?',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<DocumentProvider>();
      final success = widget.isCredit
          ? await provider.deleteCreditNote(widget.noteId)
          : await provider.deleteDebitNote(widget.noteId);

      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          Navigator.pop(context);
        } else {
          AppToast.error(context, provider.errorMessage ?? 'Failed to delete $noteType');
        }
      }
    }
  }
}
