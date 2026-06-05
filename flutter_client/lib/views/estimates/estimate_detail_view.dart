import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/toast.dart';
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
    if (mounted) {
      setState(() {
        _estimate = detail;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _estimate?['status'] ?? 'DRAFT';

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(_estimate?['proforma_number'] ?? 'Estimate Detail'),
        actions: [
          if (_estimate != null) ...[
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () {
                PrintShareHelper.showShareSheet(
                  context,
                  docLabel: 'Estimate',
                  docNumber: _estimate!['proforma_number'] ?? 'N/A',
                  docType: 'proforma-invoices',
                  docId: widget.estimateId,
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
                      builder: (_) => EstimateFormView(editEstimate: _estimate),
                    ),
                  ).then((_) => _fetchDetail());
                },
                tooltip: 'Edit estimate',
              ),
            const SizedBox(width: 8),
            StatusBadge(label: status),
            const SizedBox(width: 16),
          ],
        ],
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading estimate...')
          : _estimate == null
              ? const ErrorState(message: 'Estimate details not found.')
              : SingleChildScrollView(
                  padding: AppSpacing.pagePadding,
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
                                    Icons.request_quote_outlined,
                                    size: 20,
                                    color: AppColors.goldAccent,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('PROFORMA INVOICE / ESTIMATE', style: AppTextStyles.labelSmall),
                                      Text(
                                        _estimate!['proforma_number'] ?? 'PROFORMA',
                                        style: AppTextStyles.h2,
                                      ),
                                    ],
                                  ),
                                ),
                                StatusBadge(label: status),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            InfoRow(label: 'Customer', value: _estimate!['contact']?['name'] ?? _estimate!['contact_name'] ?? 'N/A'),
                            InfoRow(label: 'Issue Date', value: _estimate!['issue_date'] ?? ''),
                            InfoRow(label: 'Due Date', value: _estimate!['due_date'] ?? ''),
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
                            if (_estimate!['lines'] == null || (_estimate!['lines'] is List ? (_estimate!['lines'] as List).isEmpty : true))
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                                child: Text('No items', style: AppTextStyles.bodySmall),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: (_estimate!['lines'] is List ? (_estimate!['lines'] as List).length : 0),
                                separatorBuilder: (context, _) => const Divider(),
                                itemBuilder: (context, i) {
                                  final line = _estimate!['lines'][i];
                                  final quantity = double.tryParse((line['quantity'] ?? 0).toString()) ?? 0;
                                  final rate = double.tryParse((line['rate'] ?? 0).toString()) ?? 0;
                                  final total = double.tryParse((line['total'] ?? 0).toString()) ?? 0;

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                line['description'] ?? line['product_name'] ?? 'Item',
                                                style: AppTextStyles.bodyMedium,
                                              ),
                                              const SizedBox(height: AppSpacing.xxs),
                                              Text(
                                                'Qty: $quantity × ₹${rate.toStringAsFixed(2)}',
                                                style: AppTextStyles.caption,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '₹${total.toStringAsFixed(2)}',
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
                            SummaryRow(label: 'Subtotal', value: '₹${(double.tryParse((_estimate!['subtotal'] ?? 0).toString()) ?? 0).toStringAsFixed(2)}'),
                            SummaryRow(label: 'Discount Total', value: '₹${(double.tryParse((_estimate!['discount_total'] ?? 0).toString()) ?? 0).toStringAsFixed(2)}'),
                            SummaryRow(label: 'CGST', value: '₹${(double.tryParse((_estimate!['cgst_amount'] ?? 0).toString()) ?? 0).toStringAsFixed(2)}'),
                            SummaryRow(label: 'SGST', value: '₹${(double.tryParse((_estimate!['sgst_amount'] ?? 0).toString()) ?? 0).toStringAsFixed(2)}'),
                            SummaryRow(label: 'IGST', value: '₹${(double.tryParse((_estimate!['igst_amount'] ?? 0).toString()) ?? 0).toStringAsFixed(2)}'),
                            SummaryRow(label: 'Round Off', value: '₹${(double.tryParse((_estimate!['round_off'] ?? 0).toString()) ?? 0).toStringAsFixed(2)}'),
                            const Divider(),
                            SummaryRow(
                              label: 'Total Amount',
                              value: '₹${(double.tryParse((_estimate!['total'] ?? 0).toString()) ?? 0).toStringAsFixed(2)}',
                              isBold: true,
                              valueColor: AppColors.brandNavy,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (status == 'DRAFT') ...[
                        ActionButton(
                          label: 'Issue Estimate',
                          icon: Icons.send_outlined,
                          tier: ActionTier.warning,
                          onPressed: _issueEstimate,
                        ),
                        const SizedBox(height: 12),
                        ActionButton(
                          label: 'Delete Draft',
                          icon: Icons.delete_outline,
                          tier: ActionTier.dangerous,
                          onPressed: _deleteEstimate,
                        ),
                      ],
                      if (status == 'ISSUED') ...[
                        ActionButton(
                          label: 'Convert to Sales Invoice',
                          icon: Icons.transform_outlined,
                          tier: ActionTier.safe,
                          onPressed: _convertToInvoice,
                        ),
                        const SizedBox(height: 12),
                        ActionButton(
                          label: 'Cancel Estimate',
                          icon: Icons.cancel_outlined,
                          tier: ActionTier.dangerous,
                          onPressed: _cancelEstimate,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xxxl),
                    ],
                  ),
                ),
    );
  }

  void _deleteEstimate() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Delete Draft Estimate?',
      message: 'Are you sure you want to permanently delete this draft estimate?',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<DocumentProvider>();
      final success = await provider.deleteEstimate(widget.estimateId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          Navigator.pop(context);
        } else {
          AppToast.error(context, provider.errorMessage ?? 'Failed to delete estimate');
        }
      }
    }
  }

  void _issueEstimate() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Issue Estimate?',
      message: 'This will lock the estimate and mark it as ISSUED, allowing it to be sent and converted.',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<DocumentProvider>();
      final success = await provider.issueEstimate(widget.estimateId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _fetchDetail();
        } else {
          AppToast.error(context, provider.errorMessage ?? 'Failed to issue estimate');
        }
      }
    }
  }

  void _convertToInvoice() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Convert to Invoice?',
      message: 'This will generate a new Sales Invoice Draft from this estimate. The estimate status will be updated.',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<DocumentProvider>();
      final success = await provider.convertEstimate(widget.estimateId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          AppToast.success(context, 'Successfully converted to Sales Invoice!');
          _fetchDetail();
        } else {
          AppToast.error(context, provider.errorMessage ?? 'Failed to convert estimate');
        }
      }
    }
  }

  void _cancelEstimate() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel Estimate?',
      message: 'Are you sure you want to cancel this estimate? This action is permanent.',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<DocumentProvider>();
      final success = await provider.cancelEstimate(widget.estimateId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _fetchDetail();
        } else {
          AppToast.error(context, provider.errorMessage ?? 'Failed to cancel estimate');
        }
      }
    }
  }
}
