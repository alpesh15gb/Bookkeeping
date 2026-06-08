import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
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

  @override
  Widget build(BuildContext context) {
    final est = _estimate;
    final status = est?['status'] ?? 'DRAFT';
    final total = double.tryParse((est?['total'] ?? 0).toString()) ?? 0.0;
    final lines = est?['lines'] is List ? (est!['lines'] as List) : [];
    final contact = est?['contact'] is Map ? Map<String, dynamic>.from(est!['contact']) : null;

    return DocumentPreviewScreen(
      appBarTitle: 'Estimate',
      appBarActions: [
        IconButton(icon: const Icon(Icons.share_outlined, size: 18), onPressed: _share, tooltip: 'Share'),
      ],
      isLoading: _isLoading,
      errorMessage: est == null && !_isLoading ? 'Estimate not found.' : null,
      onRetry: _fetchDetail,
      hero: DocumentHero(
        docNumber: est?['proforma_number']?.toString() ?? 'PROFORMA',
        docType: 'Estimate',
        amount: total,
        status: status,
        issueDate: est?['issue_date']?.toString(),
        dueDate: est?['due_date']?.toString(),
      ),
      sections: [
        // ── Status Progression ──
        StatusProgression(
          states: const ['DRAFT', 'ISSUED', 'ACCEPTED', 'CONVERTED'],
          currentState: status,
          stateLabels: const {
            'DRAFT': 'Draft',
            'ISSUED': 'Issued',
            'ACCEPTED': 'Accepted',
            'CONVERTED': 'Converted',
          },
        ),
        const SizedBox(height: 16),

        // ── Customer ──
        CustomerCard(
          name: contact?['name']?.toString() ?? est?['contact_name']?.toString() ?? 'Guest',
          gstin: contact?['gstin']?.toString(),
          phone: contact?['phone']?.toString(),
          email: contact?['email']?.toString(),
          state: contact?['state_code']?.toString(),
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
                        final qty = double.tryParse((l['quantity'] ?? 0).toString()) ?? 0;
                        final rate = double.tryParse((l['rate'] ?? 0).toString()) ?? 0;
                        final total = double.tryParse((l['total'] ?? 0).toString()) ?? 0;
                        return ItemTableRow(
                          name: l['description'] ?? l['product_name'] ?? 'Item',
                          qty: qty.toStringAsFixed(0),
                          rate: AmountFormat.format(rate),
                          amount: AmountFormat.format(total),
                        );
                      }).toList(),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Tax Summary ──
        TaxSummaryHero(
          subtotal: double.tryParse((est?['subtotal'] ?? 0).toString()) ?? 0,
          cgst: double.tryParse((est?['cgst_amount'] ?? 0).toString()) ?? 0,
          sgst: double.tryParse((est?['sgst_amount'] ?? 0).toString()) ?? 0,
          igst: double.tryParse((est?['igst_amount'] ?? 0).toString()) ?? 0,
          roundOff: double.tryParse((est?['round_off'] ?? 0).toString()) ?? 0,
          total: total,
        ),
        const SizedBox(height: 16),

        // ── Notes ──
        if (est?['notes'] != null && est!['notes'].toString().isNotEmpty)
          AppCard(
            child: AppSection(
              title: 'Notes',
              child: Text(est['notes'].toString(), style: AppTextStyles.bodySmall),
            ),
          ),

        // ── Timeline ──
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Activity'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              AppTimeline(items: [
                AppTimelineItem(
                  title: 'Estimate Created',
                  date: AppDate.format(est?['issue_date']?.toString()),
                  color: AppColors.brandNavy,
                ),
                if (status != 'DRAFT')
                  AppTimelineItem(
                    title: 'Estimate Issued',
                    date: AppDate.format(est?['issue_date']?.toString()),
                    color: AppColors.info,
                  ),
                if (status == 'CONVERTED')
                  AppTimelineItem(
                    title: 'Converted to Invoice',
                    color: AppColors.success,
                  ),
                if (status == 'CANCELLED')
                  AppTimelineItem(
                    title: 'Estimate Cancelled',
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
        const SizedBox(height: 8),
        AppButton(label: 'Duplicate', icon: Icons.copy_outlined, onTap: () => AppToast.info(context, 'Duplicate')),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        if (status == 'DRAFT') ...[
          AppButton(label: 'Issue Estimate', icon: Icons.send_outlined, onTap: _issue, isPrimary: true),
          const SizedBox(height: 8),
          AppButton(label: 'Delete Draft', icon: Icons.delete_outline, onTap: _delete, color: AppColors.error),
        ],
        if (status == 'ISSUED') ...[
          AppButton(label: 'Convert to Invoice', icon: Icons.transform_outlined, onTap: _convert, isPrimary: true),
          const SizedBox(height: 8),
          AppButton(label: 'Cancel Estimate', icon: Icons.cancel_outlined, onTap: _cancel, color: AppColors.error),
        ],
        if (status == 'ACCEPTED') ...[
          AppButton(label: 'Convert to Invoice', icon: Icons.transform_outlined, onTap: _convert, isPrimary: true),
        ],
      ],
    );
  }
}
