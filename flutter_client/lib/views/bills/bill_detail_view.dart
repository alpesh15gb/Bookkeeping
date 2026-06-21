import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/bill_provider.dart';
import 'package:flutter_client/models/bill.dart';
import 'package:flutter_client/views/shared/app_components.dart' hide AppCard;
import 'package:flutter_client/views/shared/design_system.dart';
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
    final remaining = (_bill?.total ?? 0) - (_bill?.amountPaid ?? 0);
    if (remaining <= 0) {
      AppToast.error(context, 'Bill is already fully paid');
      return;
    }
    AppToast.info(context, 'Payment dialog would open here');
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'DRAFT': return AppColors.textMuted;
      case 'POSTED': return AppColors.info;
      case 'PARTIALLY_PAID': return AppColors.warning;
      case 'PAID': return AppColors.success;
      case 'CANCELLED': return AppColors.error;
      default: return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = _bill;
    final status = bill?.status ?? 'DRAFT';
    final total = bill?.total ?? 0;
    final contact = bill?.contact;
    final contactName = contact?.name ?? 'Vendor';
    final amountPaid = bill?.amountPaid ?? 0;
    final balance = total - amountPaid;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(bill?.billNumber ?? 'Bill'),
        actions: [
          IconButton(icon: const Icon(Icons.share_outlined, size: 18), onPressed: _share, tooltip: 'Share'),
          IconButton(icon: const Icon(Icons.print_outlined, size: 18), onPressed: _share, tooltip: 'Print'),
        ],
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading bill...')
          : bill == null
              ? const ErrorState(message: 'Bill not found.')
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeaderCard(bill, status, total, contactName),
                            const SizedBox(height: 12),
                            _buildPaymentProgress(total, amountPaid, balance, status),
                            const SizedBox(height: 12),
                            if (contact != null) ...[
                              _buildCustomerCard(contact, contactName, balance),
                              const SizedBox(height: 12),
                            ],
                            _buildItemsCard(bill),
                            const SizedBox(height: 12),
                            _buildTaxSummary(bill, total),
                            const SizedBox(height: 12),
                            _buildTimeline(bill, status, amountPaid),
                          ],
                        ),
                      ),
                    ),
                    _buildActionBar(status, balance),
                  ],
                ),
    );
  }

  Widget _buildHeaderCard(BillModel bill, String status, double total, String contactName) {
    final color = _statusColor(status);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('VENDOR BILL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.7), letterSpacing: 1)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                  child: Text(status, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(bill.billNumber, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 4),
            Text(contactName, style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8))),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildHeaderStat('AMOUNT', AmountFormat.format(total)),
                const SizedBox(width: 24),
                _buildHeaderStat('ITEMS', '${bill.lines.length}'),
                ...[
                const SizedBox(width: 24),
                _buildHeaderStat('DATE', AppDate.format(bill.billDate)),
              ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.6), letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
      ],
    );
  }

  Widget _buildPaymentProgress(double total, double amountPaid, double balance, String status) {
    final progress = total > 0 ? (amountPaid / total).clamp(0.0, 1.0) : 0.0;
    final isPaid = status == 'PAID';
    final color = isPaid ? AppColors.success : balance > 0 && amountPaid > 0 ? AppColors.warning : AppColors.brandNavy;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('PAYMENT STATUS'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(status.replaceAll('_', ' '), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: AppColors.border, valueColor: AlwaysStoppedAnimation(color)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildPayStat('Paid', AmountFormat.format(amountPaid), AppColors.success)),
              Container(width: 1, height: 24, color: AppColors.borderLight, margin: const EdgeInsets.symmetric(horizontal: 12)),
              Expanded(child: _buildPayStat('Balance', AmountFormat.format(balance), balance > 0 ? AppColors.warning : AppColors.success)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPayStat(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: valueColor, fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
  }

  Widget _buildCustomerCard(dynamic contact, String name, double balance) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VENDOR'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              AppAvatar(name: name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                    if (contact.gstin != null && contact.gstin!.isNotEmpty)
                      Text('GSTIN: ${contact.gstin}', style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              if (balance > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text('Due: ${AmountFormat.format(balance)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning)),
                ),
            ],
          ),
          if (contact.phone != null || contact.email != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                if (contact.phone != null && contact.phone!.isNotEmpty) ...[
                  Icon(Icons.phone_outlined, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(contact.phone!, style: AppTextStyles.bodySmall),
                ],
                if (contact.phone != null && contact.email != null)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Container(width: 1, height: 12, color: AppColors.border)),
                if (contact.email != null && contact.email!.isNotEmpty) ...[
                  Icon(Icons.email_outlined, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(contact.email!, style: AppTextStyles.bodySmall),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsCard(BillModel bill) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ITEMS'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
              Text('${bill.lines.length} items', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppColors.bgLight, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text('ITEM', style: AppTextStyles.labelSmall)),
                Expanded(flex: 2, child: Text('QTY', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('RATE', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text('AMOUNT', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ...bill.lines.map((l) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderLight, width: 0.5))),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.productName ?? 'Product', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500)),
                      if (l.hsnSac.isNotEmpty)
                        Text('HSN: ${l.hsnSac}', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                Expanded(flex: 2, child: Text(l.quantity.toStringAsFixed(0), style: AppTextStyles.bodySmall, textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text(AmountFormat.format(l.rate), style: AppTextStyles.bodySmall, textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text(AmountFormat.format(l.total), style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildTaxSummary(BillModel bill, double total) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TAX SUMMARY'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          _buildSummaryRow('Subtotal', AmountFormat.format(bill.subtotal), false),
          if (bill.cgstAmount > 0) _buildSummaryRow('CGST', AmountFormat.format(bill.cgstAmount), false),
          if (bill.sgstAmount > 0) _buildSummaryRow('SGST', AmountFormat.format(bill.sgstAmount), false),
          if (bill.igstAmount > 0) _buildSummaryRow('IGST', AmountFormat.format(bill.igstAmount), false),
          if (bill.roundOff != 0) _buildSummaryRow('Round Off', AmountFormat.format(bill.roundOff), false),
          const Divider(height: 20),
          Row(
            children: [
              Text('TOTAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              Text(AmountFormat.format(total), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.brandNavy, fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, bool isBold) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: isBold ? FontWeight.w600 : FontWeight.w400)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: isBold ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildTimeline(BillModel bill, String status, double amountPaid) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ACTIVITY'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          AppTimeline(items: [
            AppTimelineItem(title: 'Bill Created', date: AppDate.format(bill.billDate), color: AppColors.brandNavy),
            if (status != 'DRAFT')
              AppTimelineItem(title: 'Bill $status', date: AppDate.format(bill.billDate), color: AppColors.success),
            if (amountPaid > 0)
              AppTimelineItem(title: 'Payment Recorded', subtitle: AmountFormat.format(amountPaid), color: AppColors.goldAccent),
          ]),
        ],
      ),
    );
  }

  Widget _buildActionBar(String status, double balance) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(color: AppColors.bgSurface, border: Border(top: BorderSide(color: AppColors.border))),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == 'DRAFT') ...[
              SizedBox(width: double.infinity, child: AppButton(label: 'Finalize Bill', icon: Icons.lock_outline, onTap: _finalize, isPrimary: true)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: AppButton(label: 'Edit', icon: Icons.edit_outlined, onTap: _edit)),
                  const SizedBox(width: 6),
                  Expanded(child: AppButton(label: 'Delete', icon: Icons.delete_outline, onTap: _delete, color: AppColors.error)),
                ],
              ),
            ] else if (status == 'POSTED' || status == 'PARTIALLY_PAID') ...[
              if (balance > 0)
                SizedBox(width: double.infinity, child: AppButton(label: 'Record Payment', icon: Icons.payment, onTap: _recordPayment, isPrimary: true)),
              if (balance > 0) const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: AppButton(label: 'Share', icon: Icons.share_outlined, onTap: _share)),
                  const SizedBox(width: 6),
                  Expanded(child: AppButton(label: 'Cancel', icon: Icons.cancel_outlined, onTap: _cancel, color: AppColors.error)),
                ],
              ),
            ] else if (status == 'PAID') ...[
              Row(
                children: [
                  Expanded(child: AppButton(label: 'Share', icon: Icons.share_outlined, onTap: _share)),
                  const SizedBox(width: 6),
                  Expanded(child: AppButton(label: 'Print', icon: Icons.print_outlined, onTap: _share)),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(child: AppButton(label: 'Share', icon: Icons.share_outlined, onTap: _share)),
                  const SizedBox(width: 6),
                  Expanded(child: AppButton(label: 'Cancel', icon: Icons.cancel_outlined, onTap: _cancel, color: AppColors.error)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
