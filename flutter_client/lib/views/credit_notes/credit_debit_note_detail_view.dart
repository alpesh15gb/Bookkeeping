import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart' hide AppCard;
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/credit_notes/credit_debit_note_form_view.dart';
import 'package:flutter_client/core/print_share_helper.dart';

class CreditDebitNoteDetailView extends StatefulWidget {
  final String noteId;
  final bool isCredit;

  const CreditDebitNoteDetailView({super.key, required this.noteId, required this.isCredit});

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
    if (mounted) setState(() { _note = detail; _isLoading = false; });
  }

  void _share() {
    final number = widget.isCredit ? _note!['credit_note_number'] : _note!['debit_note_number'];
    PrintShareHelper.showShareSheet(
      context,
      docLabel: widget.isCredit ? 'Credit Note' : 'Debit Note',
      docNumber: number ?? 'N/A',
      docType: widget.isCredit ? 'invoices/credit-notes' : 'invoices/debit-notes',
      docId: widget.noteId,
    );
  }

  void _edit() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreditDebitNoteFormView(isCredit: widget.isCredit, editNote: _note)),
    ).then((updated) { if (updated == true) _fetchDetail(); });
  }

  void _finalize() async {
    final confirm = await AppConfirmDialog.show(context, title: 'Finalize Note?', message: 'This will lock the note.');
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = widget.isCredit
          ? await provider.finalizeCreditNote(widget.noteId)
          : await provider.finalizeDebitNote(widget.noteId);
      if (success && mounted) _fetchDetail();
    }
  }

  void _cancel() async {
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel Note?', message: 'This will reverse ledger entries.');
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = widget.isCredit
          ? await provider.cancelCreditNote(widget.noteId)
          : await provider.cancelDebitNote(widget.noteId);
      if (success && mounted) _fetchDetail();
    }
  }

  void _delete() async {
    final noteType = widget.isCredit ? 'Credit Note' : 'Debit Note';
    final confirm = await AppConfirmDialog.show(context, title: 'Delete Draft $noteType?', message: 'Are you sure?');
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = widget.isCredit
          ? await provider.deleteCreditNote(widget.noteId)
          : await provider.deleteDebitNote(widget.noteId);
      if (success && mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    final status = note?['status'] ?? 'DRAFT';
    final number = widget.isCredit
        ? (note != null ? note['credit_note_number']?.toString() : null)
        : (note != null ? note['debit_note_number']?.toString() : null);
    final total = double.tryParse((note?['total'] ?? 0).toString()) ?? 0.0;
    final lines = note?['lines'] is List ? (note!['lines'] as List) : [];
    final contactName = note?['contact_name']?.toString();

    return DocumentPreviewScreen(
      appBarTitle: widget.isCredit ? 'Credit Note' : 'Debit Note',
      appBarActions: [
        IconButton(icon: const Icon(Icons.share_outlined, size: 18), onPressed: _share, tooltip: 'Share'),
      ],
      isLoading: _isLoading,
      errorMessage: note == null && !_isLoading ? 'Note not found.' : null,
      onRetry: _fetchDetail,
      hero: DocumentHero(
        docNumber: number ?? 'NOTE',
        docType: widget.isCredit ? 'Credit Note' : 'Debit Note',
        amount: total,
        status: status,
        issueDate: note?['issue_date']?.toString(),
      ),
      sections: [
        // ── Status Progression ──
        StatusProgression(
          states: ['DRAFT', 'POSTED', 'CANCELLED'],
          currentState: status,
          stateLabels: const {
            'DRAFT': 'Draft',
            'POSTED': 'Posted',
            'CANCELLED': 'Cancelled',
          },
        ),
        const SizedBox(height: 16),

        // ── Context ──
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Context'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              AppInfoRow(label: 'Linked Invoice', value: note?['invoice_number']?.toString() ?? 'Unlinked'),
              AppInfoRow(label: 'Reason', value: note?['reason']?.toString() ?? 'N/A'),
              if (contactName != null) AppInfoRow(label: 'Customer / Vendor', value: contactName),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Items ──
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Items'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              lines.isEmpty
                  ? Text('No items', style: AppTextStyles.bodySmall)
                  : ItemTable(
                      items: lines.map((l) {
                        final qty = double.tryParse((l['quantity'] ?? 0).toString()) ?? 0.0;
                        final rate = double.tryParse((l['rate'] ?? 0).toString()) ?? 0.0;
                        final amt = double.tryParse((l['subtotal'] ?? 0).toString()) ?? (qty * rate);
                        return ItemTableRow(
                          name: l['product_name'] ?? 'Product',
                          qty: qty.toStringAsFixed(0),
                          rate: AmountFormat.format(rate),
                          amount: AmountFormat.format(amt),
                        );
                      }).toList(),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Tax Summary ──
        TaxSummaryHero(
          subtotal: double.tryParse((note?['subtotal'] ?? 0).toString()) ?? 0.0,
          cgst: double.tryParse((note?['cgst_amount'] ?? 0).toString()) ?? 0.0,
          sgst: double.tryParse((note?['sgst_amount'] ?? 0).toString()) ?? 0.0,
          igst: double.tryParse((note?['igst_amount'] ?? 0).toString()) ?? 0.0,
          cess: double.tryParse((note?['cess_amount'] ?? 0).toString()) ?? 0.0,
          roundOff: double.tryParse((note?['round_off'] ?? 0).toString()) ?? 0.0,
          total: total,
        ),
        const SizedBox(height: 16),

        // ── Timeline ──
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Activity'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              AppTimeline(items: [
                AppTimelineItem(
                  title: '${widget.isCredit ? "Credit" : "Debit"} Note Created',
                  date: AppDate.format(note?['issue_date']?.toString()),
                  color: AppColors.warning,
                ),
                if (status == 'POSTED')
                  AppTimelineItem(
                    title: 'Note Posted',
                    color: AppColors.success,
                  ),
                if (status == 'CANCELLED')
                  AppTimelineItem(
                    title: 'Note Cancelled',
                    color: AppColors.error,
                  ),
              ]),
            ],
          ),
        ),
      ],
      actions: [
        AppButton(label: 'Edit', icon: Icons.edit_outlined, onTap: _edit, isPrimary: true),
        const SizedBox(height: 8),
        AppButton(label: 'Share', icon: Icons.share_outlined, onTap: _share),
        const SizedBox(height: 8),
        AppButton(label: 'Print', icon: Icons.print_outlined, onTap: _share),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        if (status == 'DRAFT') ...[
          AppButton(label: 'Finalize', icon: Icons.lock_outline, onTap: _finalize, isPrimary: true),
          const SizedBox(height: 8),
          AppButton(label: 'Delete', icon: Icons.delete_outline, onTap: _delete, color: AppColors.error),
        ],
        if (status == 'POSTED') ...[
          AppButton(label: 'Cancel Note', icon: Icons.cancel_outlined, onTap: _cancel, color: AppColors.error),
        ],
      ],
    );
  }
}
