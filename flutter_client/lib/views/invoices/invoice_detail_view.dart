import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/invoice_provider.dart';
import 'package:flutter_client/models/invoice.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/invoices/invoice_form_view.dart';
import 'package:flutter_client/views/payments/payment_form_view.dart';
import 'package:flutter_client/core/print_share_helper.dart';

class InvoiceDetailView extends StatefulWidget {
  final String invoiceId;
  const InvoiceDetailView({super.key, required this.invoiceId});

  @override
  State<InvoiceDetailView> createState() => _InvoiceDetailViewState();
}

class _InvoiceDetailViewState extends State<InvoiceDetailView> {
  InvoiceModel? _invoice;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  void _fetchDetail() async {
    final detail = await context.read<InvoiceProvider>().fetchInvoiceDetail(widget.invoiceId);
    if (mounted) setState(() { _invoice = detail; _isLoading = false; });
  }

  void _edit() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceFormView(editInvoice: _invoice)),
    ).then((_) => _fetchDetail());
  }

  void _share() {
    PrintShareHelper.showShareSheet(
      context,
      docLabel: 'Invoice',
      docNumber: _invoice!.invoiceNumber,
      docType: 'invoices',
      docId: _invoice!.id,
    );
  }

  void _cancel() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel Invoice?',
      message: 'Cancel ${_invoice!.invoiceNumber}? This will reverse ledger entries.',
    );
    if (confirm == true) {
      final provider = context.read<InvoiceProvider>();
      final success = await provider.cancelInvoice(widget.invoiceId);
      if (success && mounted) _fetchDetail();
    }
  }

  void _recordPayment() {
    final remaining = _invoice!.total - _invoice!.amountPaid;
    if (remaining <= 0) {
      AppToast.error(context, 'Invoice is already fully paid');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentFormView(
          mode: 'receipt',
          onSuccess: () {
            Navigator.pop(context);
            _fetchDetail();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        appBar: AppBar(title: const Text('Invoice')),
        body: const LoadingState(message: 'Loading invoice...'),
      );
    }

    if (_invoice == null) {
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        appBar: AppBar(title: const Text('Invoice')),
        body: const ErrorState(message: 'Invoice not found.'),
      );
    }

    final inv = _invoice!;
    final contact = inv.contact;

    return DocumentPreviewScreen(
      appBarTitle: 'Invoice',
      appBarActions: [
        IconButton(icon: const Icon(Icons.share_outlined, size: 18), onPressed: _share, tooltip: 'Share'),
      ],
      hero: DocumentHero(
        docNumber: inv.invoiceNumber,
        docType: 'Invoice',
        amount: inv.total,
        status: inv.status,
        issueDate: inv.issueDate,
        dueDate: inv.dueDate,
      ),
      sections: [
        // ── Customer ──
        CustomerCard(
          name: contact?.name ?? inv.contactName ?? 'Guest',
          gstin: contact?.gstin,
          phone: contact?.phone,
          email: contact?.email,
          state: contact?.stateCode,
          outstandingBalance: inv.total - inv.amountPaid,
          address: _formatAddress(contact?.billingAddress),
        ),
        const SizedBox(height: 16),

        // ── Items ──
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Items'.toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),
              ItemTable(
                items: inv.lines.map((l) => ItemTableRow(
                  name: l.productName ?? 'Product',
                  qty: l.quantity.toStringAsFixed(0),
                  rate: AmountFormat.format(l.rate),
                  amount: AmountFormat.format(l.total),
                  hsn: l.hsnSac.isNotEmpty ? l.hsnSac : null,
                  gstRate: l.gstRate > 0 ? l.gstRate : null,
                )).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Tax Summary ──
        TaxSummaryHero(
          subtotal: inv.subtotal,
          cgst: inv.cgstAmount > 0 ? inv.cgstAmount : null,
          sgst: inv.sgstAmount > 0 ? inv.sgstAmount : null,
          igst: inv.igstAmount > 0 ? inv.igstAmount : null,
          cess: inv.cessAmount > 0 ? inv.cessAmount : null,
          roundOff: inv.roundOff != 0 ? inv.roundOff : null,
          total: inv.total,
        ),
        const SizedBox(height: 16),

        // ── Notes ──
        if (inv.notes != null && inv.notes!.isNotEmpty)
          AppCard(
            child: AppSection(
              title: 'Notes',
              child: Text(inv.notes!, style: AppTextStyles.bodySmall),
            ),
          ),

        // ── Timeline ──
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Activity'.toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),
              AppTimeline(items: [
                AppTimelineItem(
                  title: 'Invoice Created',
                  subtitle: 'By ${inv.contactName ?? 'System'}',
                  date: AppDate.format(inv.issueDate),
                  color: AppColors.brandNavy,
                ),
                if (inv.status != 'DRAFT')
                  AppTimelineItem(
                    title: 'Invoice ${inv.status}',
                    date: AppDate.format(inv.issueDate),
                    color: AppColors.success,
                  ),
                if (inv.amountPaid > 0)
                  AppTimelineItem(
                    title: 'Payment Received',
                    subtitle: AmountFormat.format(inv.amountPaid),
                    color: AppColors.goldAccent,
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
        const SizedBox(height: 8),
        AppButton(label: 'Duplicate', icon: Icons.copy_outlined, onTap: () => AppToast.info(context, 'Duplicate')),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        if (inv.status == 'DRAFT') ...[
          AppButton(label: 'Finalize', icon: Icons.lock_outline, onTap: () => AppToast.info(context, 'Finalize'), isPrimary: true),
          const SizedBox(height: 8),
          AppButton(label: 'Delete', icon: Icons.delete_outline, onTap: () => AppToast.info(context, 'Delete'), color: AppColors.error),
        ],
        if (inv.status == 'SENT' || inv.status == 'PARTIALLY_PAID') ...[
          AppButton(label: 'Receive Payment', icon: Icons.payment, onTap: _recordPayment, isPrimary: true),
          const SizedBox(height: 8),
          AppButton(label: 'Cancel Invoice', icon: Icons.cancel_outlined, onTap: _cancel, color: AppColors.error),
        ],
        if (inv.status == 'PAID') ...[
          AppButton(label: 'Cancel Invoice', icon: Icons.cancel_outlined, onTap: _cancel, color: AppColors.error),
        ],
      ],
    );
  }

  String _formatAddress(Map<String, dynamic>? addr) {
    if (addr == null) return '';
    final parts = <String>[];
    if (addr['address_line_1'] != null) parts.add(addr['address_line_1'].toString());
    if (addr['address_line_2'] != null) parts.add(addr['address_line_2'].toString());
    if (addr['city'] != null) parts.add(addr['city'].toString());
    if (addr['state'] != null) parts.add(addr['state'].toString());
    if (addr['pincode'] != null) parts.add(addr['pincode'].toString());
    return parts.join(', ');
  }
}
