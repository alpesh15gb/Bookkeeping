import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/delivery_challan_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/delivery_challans/delivery_challan_form_view.dart';

class DeliveryChallanDetailView extends StatefulWidget {
  final String challanId;

  const DeliveryChallanDetailView({super.key, required this.challanId});

  @override
  State<DeliveryChallanDetailView> createState() => _DeliveryChallanDetailViewState();
}

class _DeliveryChallanDetailViewState extends State<DeliveryChallanDetailView> {
  Map<String, dynamic>? _challan;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _fetch() async {
    final detail = await context.read<DeliveryChallanProvider>().fetchChallanDetail(widget.challanId);
    if (mounted) setState(() { _challan = detail; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: LoadingState(message: 'Loading...'));
    if (_challan == null) return const Scaffold(body: ErrorState(message: 'Challan not found'));

    final c = _challan!;
    final status = c['status'] ?? 'DRAFT';

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(c['challan_number'] ?? 'Challan Detail'),
        actions: [
          if (status == 'DRAFT')
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeliveryChallanFormView(challan: c))).then((_) => _fetch()), tooltip: 'Edit'),
          StatusBadge(label: status),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Column(
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFE57C00).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.local_shipping_rounded, size: 20, color: Color(0xFFE57C00))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('DELIVERY CHALLAN', style: AppTextStyles.labelSmall), Text(c['challan_number'] ?? 'N/A', style: AppTextStyles.h2)])),
                  ]),
                  const SizedBox(height: 16),
                  const Divider(),
                  InfoRow(label: 'Customer', value: c['contact_name'] ?? c['customer_name'] ?? 'N/A'),
                  InfoRow(label: 'Issue Date', value: c['issued_date'] ?? c['issue_date'] ?? 'N/A'),
                  InfoRow(label: 'Notes', value: c['notes'] ?? '-'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'ITEMS DISPATCHED'),
                  ...((c['lines'] as List?) ?? []).map((l) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(l['product_name'] ?? 'N/A', style: AppTextStyles.bodySmall)),
                        Text('${l['quantity']} ${l['uom'] ?? 'nos'}', style: AppTextStyles.caption),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (status == 'DRAFT')
              ActionButton(label: 'Issue Challan', tier: ActionTier.safe, onPressed: () async {
                final ok = await AppConfirmDialog.show(context, title: 'Issue?', message: 'Issue this delivery challan?');
                if (ok == true) {
                  final success = await context.read<DeliveryChallanProvider>().issueChallan(widget.challanId);
                  if (success) { _fetch(); } else if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<DeliveryChallanProvider>().errorMessage ?? 'Failed'), backgroundColor: AppColors.error)); }
                }
              }),
            if (status == 'ISSUED' || status == 'DRAFT') ...[
              const SizedBox(height: 12),
              ActionButton(label: 'Cancel Challan', tier: ActionTier.dangerous, onPressed: () async {
                final ok = await AppConfirmDialog.show(context, title: 'Cancel?', message: 'Cancel this challan?');
                if (ok == true) {
                  final success = await context.read<DeliveryChallanProvider>().cancelChallan(widget.challanId);
                  if (success) { _fetch(); }
                }
              }),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
