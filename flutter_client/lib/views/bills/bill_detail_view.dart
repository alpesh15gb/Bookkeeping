import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/bill_provider.dart';
import 'package:flutter_client/models/bill.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/bills/bill_form_view.dart';
import 'package:flutter_client/core/print_share_helper.dart';

class BillDetailView extends StatefulWidget {
  final String billId;
  const BillDetailView({super.key, required this.billId});

  @override
  State<BillDetailView> createState() => _BillDetailViewState();
}

class _BillDetailViewState extends State<BillDetailView> {
  BillModel? _bill;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  void _fetchDetail() async {
    final detail = await context.read<BillProvider>().fetchBillDetail(widget.billId);
    if (mounted) setState(() { _bill = detail; _isLoading = false; });
  }

  void _share() {
    PrintShareHelper.showShareSheet(
      context,
      docLabel: 'Bill',
      docNumber: _bill!.billNumber,
      docType: 'bills',
      docId: _bill!.id,
    );
  }

  void _edit() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BillFormView(editBill: _bill)),
    ).then((_) => _fetchDetail());
  }

  void _delete() async {
    final confirm = await AppConfirmDialog.show(context, title: 'Delete Draft Bill?', message: 'Are you sure?');
    if (confirm == true) {
      final provider = context.read<BillProvider>();
      final success = await provider.deleteBill(widget.billId);
      if (success && mounted) Navigator.pop(context);
    }
  }

  void _finalize() async {
    final confirm = await AppConfirmDialog.show(context, title: 'Finalize Bill?', message: 'This will lock the bill.');
    if (confirm == true) {
      final provider = context.read<BillProvider>();
      final success = await provider.finalizeBill(widget.billId);
      if (success && mounted) _fetchDetail();
    }
  }

  void _cancel() async {
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel Bill?', message: 'This will post reversals.');
    if (confirm == true) {
      final provider = context.read<BillProvider>();
      final success = await provider.cancelBill(widget.billId);
      if (success && mounted) _fetchDetail();
    }
  }

  void _recordPayment() {
    final remaining = _bill!.total - _bill!.amountPaid;
    if (remaining <= 0) {
      AppToast.error(context, 'Bill is already fully paid');
      return;
    }
    AppToast.info(context, 'Payment dialog would open here');
  }

  @override
  Widget build(BuildContext context) {
    final bill = _bill;
    final contact = bill?.contact;

    return DocumentPreviewScreen(
      appBarTitle: 'Vendor Bill',
      appBarActions: [
        IconButton(icon: const Icon(Icons.share_outlined, size: 18), onPressed: _share, tooltip: 'Share'),
      ],
      isLoading: _isLoading,
      errorMessage: bill == null && !_isLoading ? 'Bill not found.' : null,
      onRetry: _fetchDetail,
      hero: DocumentHero(
        docNumber: bill?.billNumber ?? 'BILL',
        docType: 'Vendor Bill',
        amount: bill?.total ?? 0,
        status: bill?.status ?? 'DRAFT',
        issueDate: bill?.billDate,
        dueDate: bill?.dueDate,
      ),
      sections: [
        // ── Customer ──
        CustomerCard(
          name: contact?.name ?? 'Vendor',
          gstin: contact?.gstin,
          phone: contact?.phone,
          email: contact?.email,
          state: contact?.stateCode,
          outstandingBalance: (bill?.total ?? 0) - (bill?.amountPaid ?? 0),
          partyLabel: 'Vendor',
        ),
        const SizedBox(height: 16),

        // ── Items ──
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Items'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              bill?.lines.isEmpty == true
                  ? Text('No items', style: AppTextStyles.bodySmall)
                  : ItemTable(
                      items: bill!.lines.map((l) => ItemTableRow(
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
          subtotal: bill?.subtotal ?? 0,
          cgst: (bill?.cgstAmount ?? 0) > 0 ? bill?.cgstAmount : null,
          sgst: (bill?.sgstAmount ?? 0) > 0 ? bill?.sgstAmount : null,
          igst: (bill?.igstAmount ?? 0) > 0 ? bill?.igstAmount : null,
          roundOff: (bill?.roundOff ?? 0) != 0 ? bill?.roundOff : null,
          total: bill?.total ?? 0,
        ),
        const SizedBox(height: 16),

        // ── Payment Status ──
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payment'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              AppInfoRow(label: 'Amount Paid', value: AmountFormat.format(bill?.amountPaid ?? 0)),
              AppInfoRow(label: 'Balance', value: AmountFormat.format((bill?.total ?? 0) - (bill?.amountPaid ?? 0))),
            ],
          ),
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
                  title: 'Bill Created',
                  date: AppDate.format(bill?.billDate),
                  color: AppColors.brandNavy,
                ),
                if ((bill?.amountPaid ?? 0) > 0)
                  AppTimelineItem(
                    title: 'Payment Recorded',
                    subtitle: AmountFormat.format(bill!.amountPaid),
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
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        if (bill?.status == 'DRAFT') ...[
          AppButton(label: 'Finalize', icon: Icons.lock_outline, onTap: _finalize, isPrimary: true),
          const SizedBox(height: 8),
          AppButton(label: 'Delete', icon: Icons.delete_outline, onTap: _delete, color: AppColors.error),
        ],
        if (bill?.status == 'UNPAID' || bill?.status == 'PARTIALLY_PAID') ...[
          AppButton(label: 'Record Payment', icon: Icons.payment, onTap: _recordPayment, isPrimary: true),
          const SizedBox(height: 8),
          AppButton(label: 'Cancel Bill', icon: Icons.cancel_outlined, onTap: _cancel, color: AppColors.error),
        ],
      ],
    );
  }
}
