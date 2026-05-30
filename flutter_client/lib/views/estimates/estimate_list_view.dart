import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/estimates/estimate_form_view.dart';
import 'package:flutter_client/views/estimates/estimate_detail_view.dart';

class EstimateListView extends StatefulWidget {
  const EstimateListView({super.key});

  @override
  State<EstimateListView> createState() => _EstimateListViewState();
}

class _EstimateListViewState extends State<EstimateListView> {
  List<dynamic> _estimates = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _fetch() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    final list = await context.read<DocumentProvider>().fetchEstimates();
    if (mounted) {
      setState(() {
        _estimates = list;
        _isLoading = false;
      });
    }
  }

  void _showForm({Map<String, dynamic>? estimate}) async {
    Map<String, dynamic>? fullEstimate = estimate;
    if (estimate != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      fullEstimate = await context.read<DocumentProvider>().fetchEstimateDetail(estimate['id']);
      if (mounted) Navigator.pop(context);
      if (fullEstimate == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load estimate details'), backgroundColor: AppColors.error),
          );
        }
        return;
      }
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EstimateFormView(editEstimate: fullEstimate)),
      ).then((_) => _fetch());
    }
  }

  void _showDetail(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EstimateDetailView(estimateId: id)),
    ).then((_) => _fetch());
  }

  Future<void> _cancelEstimate(String id) async {
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel?', message: 'Cancel this estimate?');
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = await provider.cancelEstimate(id);
      if (success) {
        _fetch();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Cancel failed'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading estimates...')
          : _estimates.isEmpty
              ? EmptyState(
                  icon: Icons.request_quote_outlined,
                  title: 'No estimates yet',
                  subtitle: 'Estimates and proforma invoices will appear here',
                  actionLabel: 'Create Estimate',
                  onAction: () => _showForm(),
                )
              : ListView.separated(
                  padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
                  itemCount: _estimates.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final est = _estimates[i];
                    final status = est['status'] ?? 'DRAFT';
                    return AppCard(
                      onTap: () => _showDetail(est['id']),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(est['proforma_number']?.toString() ?? 'PROFORMA', style: AppTextStyles.h3)),
                              StatusBadge(label: status),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.person_outlined, size: 14, color: AppColors.textMuted),
                              const SizedBox(width: 6),
                              Text('${est['contact_name'] ?? "N/A"}', style: AppTextStyles.bodySmall),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('₹${double.parse((est['total'] ?? 0).toString()).toStringAsFixed(2)}', style: AppTextStyles.numericLarge),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _showDetail(est['id']),
                                    icon: const Icon(Icons.remove_red_eye_outlined, size: 14),
                                    label: const Text('View'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      textStyle: AppTextStyles.buttonSmall,
                                      side: const BorderSide(color: AppColors.borderInput),
                                    ),
                                  ),
                                  if (status == 'DRAFT') ...[
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: () => _showForm(estimate: est),
                                      icon: const Icon(Icons.edit_outlined, size: 14),
                                      label: const Text('Edit'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        textStyle: AppTextStyles.buttonSmall,
                                        side: const BorderSide(color: AppColors.borderInput),
                                      ),
                                    ),
                                  ],
                                  if (status != 'CANCELLED') ...[
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: () => _cancelEstimate(est['id']),
                                      icon: const Icon(Icons.cancel_outlined, size: 14),
                                      label: const Text('Cancel'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.error,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        textStyle: AppTextStyles.buttonSmall,
                                        side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
