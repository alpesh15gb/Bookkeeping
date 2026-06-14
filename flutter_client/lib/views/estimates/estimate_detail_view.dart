import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart' hide AppCard;
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/estimates/estimate_form_view.dart';
import 'package:flutter_client/core/print_share_helper.dart';

class EstimateDetailView extends StatefulWidget {
  final String estimateId;
  const EstimateDetailView({super.key, required this.estimateId});

  @override
  State<EstimateDetailView> createState() => _EstimateDetailViewState();
}

class _EstimateDetailViewState extends State<EstimateDetailView> {
  Map<String, dynamic>? _estimate;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  void _fetchDetail() async {
    final detail = await context.read<DocumentProvider>().fetchEstimateDetail(widget.estimateId);
    if (mounted) setState(() { _estimate = detail; _isLoading = false; });
  }

  void _share() {
    PrintShareHelper.showShareSheet(
      context,
      docLabel: 'Estimate',
      docNumber: _estimate!['proforma_number'] ?? 'N/A',
      docType: 'proforma-invoices',
      docId: widget.estimateId,
    );
  }

  void _edit() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EstimateFormView(editEstimate: _estimate)),
    ).then((_) => _fetchDetail());
  }

  void _delete() async {
    final confirm = await AppConfirmDialog.show(context, title: 'Delete Draft Estimate?', message: 'Are you sure?');
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = await provider.deleteEstimate(widget.estimateId);
      if (success && mounted) Navigator.pop(context);
    }
  }

  void _issue() async {
    final confirm = await AppConfirmDialog.show(context, title: 'Issue Estimate?', message: 'This will lock the estimate.');
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = await provider.issueEstimate(widget.estimateId);
      if (success && mounted) _fetchDetail();
    }
  }

  void _convert() async {
    final confirm = await AppConfirmDialog.show(context, title: 'Convert to Invoice?', message: 'Generate a new Sales Invoice from this estimate.');
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = await provider.convertEstimate(widget.estimateId);
      if (success && mounted) _fetchDetail();
    }
  }

  void _cancel() async {
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel Estimate?', message: 'This action is permanent.');
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = await provider.cancelEstimate(widget.estimateId);
      if (success && mounted) _fetchDetail();
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'DRAFT': return AppColors.textMuted;
      case 'ISSUED': return AppColors.info;
      case 'ACCEPTED': return AppColors.success;
      case 'CONVERTED': return AppColors.brandNavy;
      case 'CANCELLED': return AppColors.error;
      default: return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final est = _estimate;
    final status = est?['status'] ?? 'DRAFT';
    final total = double.tryParse((est?['total'] ?? 0).toString()) ?? 0.0;
    final subtotal = double.tryParse((est?['subtotal'] ?? 0).toString()) ?? 0.0;
    final lines = est?['lines'] is List ? (est!['lines'] as List) : [];
    final contact = est?['contact'] is Map ? Map<String, dynamic>.from(est!['contact']) : null;
    final contactName = contact?['name']?.toString() ?? est?['contact_name']?.toString() ?? 'Guest';

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(est?['proforma_number']?.toString() ?? 'Estimate'),
        actions: [
          IconButton(icon: const Icon(Icons.share_outlined, size: 18), onPressed: _share, tooltip: 'Share'),
          IconButton(icon: const Icon(Icons.print_outlined, size: 18), onPressed: _share, tooltip: 'Print'),
        ],
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading estimate...')
          : est == null
              ? ErrorState(message: 'Estimate not found.', onRetry: _fetchDetail)
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeaderCard(est, status, total, contactName),
                            const SizedBox(height: 12),
                            _buildStatusProgression(status),
                            const SizedBox(height: 12),
                            if (contact != null) ...[
                              _buildCustomerCard(contact, contactName),
                              const SizedBox(height: 12),
                            ],
                            _buildItemsCard(lines),
                            const SizedBox(height: 12),
                            _buildTaxSummary(subtotal, est, total),
                            if (est?['notes'] != null && est!['notes'].toString().isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildNotesCard(est!['notes'].toString()),
                            ],
                            const SizedBox(height: 12),
                            _buildTimeline(est!, status),
                          ],
                        ),
                      ),
                    ),
                    _buildActionBar(status),
                  ],
                ),
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> est, String status, double total, String contactName) {
    final color = _statusColor(status);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ESTIMATE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.7), letterSpacing: 1),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(status, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              est['proforma_number']?.toString() ?? 'PROFORMA',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              contactName,
              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildHeaderStat('AMOUNT', AmountFormat.format(total)),
                const SizedBox(width: 24),
                _buildHeaderStat('ITEMS', '${est['lines'] is List ? (est['lines'] as List).length : 0}'),
                if (est['issue_date'] != null) ...[
                  const SizedBox(width: 24),
                  _buildHeaderStat('DATE', AppDate.format(est['issue_date'])),
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

  Widget _buildStatusProgression(String status) {
    const states = ['DRAFT', 'ISSUED', 'ACCEPTED', 'CONVERTED'];
    final labels = {'DRAFT': 'Draft', 'ISSUED': 'Issued', 'ACCEPTED': 'Accepted', 'CONVERTED': 'Converted'};
    final currentIndex = states.indexOf(status);
    final isCancelled = status == 'CANCELLED';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PROGRESS'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 14),
          Row(
            children: List.generate(states.length, (i) {
              final isActive = isCancelled ? i == 0 : i <= currentIndex;
              final isCurrent = isCancelled ? i == 0 : i == currentIndex;
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isActive ? _statusColor(states[i]) : AppColors.border,
                              border: isCurrent ? Border.all(color: _statusColor(states[i]), width: 2) : null,
                              boxShadow: isCurrent ? [BoxShadow(color: _statusColor(states[i]).withValues(alpha: 0.3), blurRadius: 6)] : null,
                            ),
                            child: Center(
                              child: isCancelled && i == 0
                                  ? const Icon(Icons.cancel_outlined, size: 14, color: Colors.white)
                                  : isActive
                                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                                      : Text('${i + 1}', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(labels[states[i]] ?? '', style: TextStyle(fontSize: 9, fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500, color: isCurrent ? _statusColor(states[i]) : AppColors.textMuted)),
                        ],
                      ),
                    ),
                    if (i < states.length - 1)
                      Container(
                        height: 2,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: isCancelled ? AppColors.border : i < currentIndex ? _statusColor(states[i + 1]) : AppColors.border,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> contact, String name) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CUSTOMER'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
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
                    if (contact['gstin'] != null && contact['gstin'].toString().isNotEmpty)
                      Text('GSTIN: ${contact['gstin']}', style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (contact['phone'] != null || contact['email'] != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                if (contact['phone'] != null && contact['phone'].toString().isNotEmpty) ...[
                  Icon(Icons.phone_outlined, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(contact['phone'], style: AppTextStyles.bodySmall),
                ],
                if (contact['phone'] != null && contact['email'] != null)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Container(width: 1, height: 12, color: AppColors.border)),
                if (contact['email'] != null && contact['email'].toString().isNotEmpty) ...[
                  Icon(Icons.email_outlined, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(contact['email'], style: AppTextStyles.bodySmall),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsCard(List lines) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ITEMS'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
              Text('${lines.length} items', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 12),
          if (lines.isEmpty)
            Text('No items', style: AppTextStyles.bodySmall)
          else ...[
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
            ...lines.map((l) {
              final qty = double.tryParse((l['quantity'] ?? 0).toString()) ?? 0;
              final rate = double.tryParse((l['rate'] ?? 0).toString()) ?? 0;
              final amount = double.tryParse((l['total'] ?? 0).toString()) ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.borderLight, width: 0.5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(l['description'] ?? l['product_name'] ?? 'Item', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500)),
                    ),
                    Expanded(flex: 2, child: Text(qty.toStringAsFixed(0), style: AppTextStyles.bodySmall, textAlign: TextAlign.center)),
                    Expanded(flex: 2, child: Text(AmountFormat.format(rate), style: AppTextStyles.bodySmall, textAlign: TextAlign.right)),
                    Expanded(flex: 2, child: Text(AmountFormat.format(amount), style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildTaxSummary(double subtotal, Map<String, dynamic> est, double total) {
    final cgst = double.tryParse((est['cgst_amount'] ?? 0).toString()) ?? 0;
    final sgst = double.tryParse((est['sgst_amount'] ?? 0).toString()) ?? 0;
    final igst = double.tryParse((est['igst_amount'] ?? 0).toString()) ?? 0;
    final roundOff = double.tryParse((est['round_off'] ?? 0).toString()) ?? 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TAX SUMMARY'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          _buildSummaryRow('Subtotal', AmountFormat.format(subtotal), false),
          if (cgst > 0) _buildSummaryRow('CGST', AmountFormat.format(cgst), false),
          if (sgst > 0) _buildSummaryRow('SGST', AmountFormat.format(sgst), false),
          if (igst > 0) _buildSummaryRow('IGST', AmountFormat.format(igst), false),
          if (roundOff != 0) _buildSummaryRow('Round Off', AmountFormat.format(roundOff), false),
          const Divider(height: 20),
          Row(
            children: [
              Text('TOTAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              Text(
                AmountFormat.format(total),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.brandNavy, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
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

  Widget _buildNotesCard(String notes) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NOTES'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Text(notes, style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }

  Widget _buildTimeline(Map<String, dynamic> est, String status) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ACTIVITY'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          AppTimeline(items: [
            AppTimelineItem(
              title: 'Estimate Created',
              date: AppDate.format(est['issue_date']?.toString()),
              color: AppColors.brandNavy,
            ),
            if (status != 'DRAFT')
              AppTimelineItem(
                title: 'Estimate Issued',
                date: AppDate.format(est['issue_date']?.toString()),
                color: AppColors.info,
              ),
            if (status == 'CONVERTED')
              AppTimelineItem(title: 'Converted to Invoice', color: AppColors.success),
            if (status == 'CANCELLED')
              AppTimelineItem(title: 'Estimate Cancelled', color: AppColors.error),
          ]),
        ],
      ),
    );
  }

  Widget _buildActionBar(String status) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == 'DRAFT') ...[
              SizedBox(
                width: double.infinity,
                child: AppButton(label: 'Issue Estimate', icon: Icons.send_outlined, onTap: _issue, isPrimary: true),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: AppButton(label: 'Edit', icon: Icons.edit_outlined, onTap: _edit)),
                  const SizedBox(width: 6),
                  Expanded(child: AppButton(label: 'Delete', icon: Icons.delete_outline, onTap: _delete, color: AppColors.error)),
                ],
              ),
            ] else if (status == 'ISSUED') ...[
              SizedBox(
                width: double.infinity,
                child: AppButton(label: 'Convert to Invoice', icon: Icons.transform_outlined, onTap: _convert, isPrimary: true),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: AppButton(label: 'Share', icon: Icons.share_outlined, onTap: _share)),
                  const SizedBox(width: 6),
                  Expanded(child: AppButton(label: 'Cancel', icon: Icons.cancel_outlined, onTap: _cancel, color: AppColors.error)),
                ],
              ),
            ] else if (status == 'ACCEPTED') ...[
              SizedBox(
                width: double.infinity,
                child: AppButton(label: 'Convert to Invoice', icon: Icons.transform_outlined, onTap: _convert, isPrimary: true),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(child: AppButton(label: 'Share', icon: Icons.share_outlined, onTap: _share)),
                  const SizedBox(width: 6),
                  Expanded(child: AppButton(label: 'Print', icon: Icons.print_outlined, onTap: _share)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
