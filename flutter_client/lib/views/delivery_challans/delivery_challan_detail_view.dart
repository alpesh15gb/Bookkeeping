import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/delivery_challan_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart' hide AppCard;
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/delivery_challans/delivery_challan_form_view.dart';
import 'package:flutter_client/views/invoices/invoice_form_view.dart';

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

  void _edit() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DeliveryChallanFormView(challan: _challan))).then((_) => _fetch());
  }

  void _issue() async {
    final ok = await AppConfirmDialog.show(context, title: 'Issue?', message: 'Issue this delivery challan?');
    if (ok == true) {
      final success = await context.read<DeliveryChallanProvider>().issueChallan(widget.challanId);
      if (success) _fetch();
    }
  }

  void _cancel() async {
    final ok = await AppConfirmDialog.show(context, title: 'Cancel?', message: 'Cancel this challan?');
    if (ok == true) {
      final success = await context.read<DeliveryChallanProvider>().cancelChallan(widget.challanId);
      if (success) _fetch();
    }
  }

  void _convertToInvoice() {
    final c = _challan!;
    final lines = (c['lines'] is List ? c['lines'] as List : []);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceFormView(initialData: {
          'contact_id': c['contact_id'],
          'contact_name': c['contact_name'] ?? c['customer_name'],
          'reference_number': c['challan_number'],
          'pos_state_code': c['pos_state_code'],
          'lines': lines.map((l) => {
            'product_id': l['product_id'],
            'product_name': l['product_name'],
            'quantity': l['quantity'],
            'rate': l['rate'] ?? 0,
            'discount': l['discount'] ?? 0,
            'hsn_sac': l['hsn_sac'] ?? '',
            'gst_rate': l['gst_rate'] ?? 0,
          }).toList(),
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _challan;
    final status = c?['status'] ?? 'DRAFT';
    final issueDate = AppDate.format(c?['issued_date']?.toString());
    final lines = (c?['lines'] is List ? c!['lines'] as List : []);

    return DocumentPreviewScreen(
      appBarTitle: 'Delivery Challan',
      appBarActions: [
        if (status == 'DRAFT')
          IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: _edit, tooltip: 'Edit'),
      ],
      isLoading: _isLoading,
      errorMessage: c == null && !_isLoading ? 'Challan not found.' : null,
      onRetry: _fetch,
      hero: DocumentHero(
        docNumber: c?['challan_number']?.toString() ?? 'CHALLAN',
        docType: 'Delivery Challan',
        amount: 0, // No amount for delivery challan
        status: status,
        issueDate: c?['issue_date']?.toString(),
      ),
      sections: [
        // ── Status Progression ──
        StatusProgression(
          states: ['DRAFT', 'ISSUED', 'DELIVERED'],
          currentState: status,
          stateLabels: const {
            'DRAFT': 'Draft',
            'ISSUED': 'Issued',
            'DELIVERED': 'Delivered',
          },
        ),
        const SizedBox(height: 16),

        // ── Customer ──
        CustomerCard(
          name: c?['contact_name']?.toString() ?? c?['customer_name']?.toString() ?? 'Customer',
        ),
        const SizedBox(height: 16),

        // ── Items Dispatched ──
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Items Dispatched'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              lines.isEmpty
                  ? Text('No items', style: AppTextStyles.bodySmall)
                  : ItemTable(
                      items: lines.map((l) => ItemTableRow(
                        name: l['product_name'] ?? 'N/A',
                        qty: '${l['quantity']} ${l['uom'] ?? 'nos'}',
                        rate: '-',
                        amount: '-',
                      )).toList(),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Notes ──
        if (c?['notes'] != null && c!['notes'].toString().isNotEmpty)
          AppCard(
            child: AppSection(
              title: 'Notes',
              child: Text(c['notes'].toString(), style: AppTextStyles.bodySmall),
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
                  title: 'Challan Created',
                  date: issueDate,
                  color: AppColors.brandNavy,
                ),
                if (status == 'ISSUED')
                  AppTimelineItem(
                    title: 'Challan Issued',
                    color: AppColors.info,
                  ),
                if (status == 'DELIVERED')
                  AppTimelineItem(
                    title: 'Delivered',
                    color: AppColors.success,
                  ),
              ]),
            ],
          ),
        ),
      ],
      actions: [
        if (status == 'DRAFT') ...[
          AppButton(label: 'Edit', icon: Icons.edit_outlined, onTap: _edit, isPrimary: true),
          const SizedBox(height: 8),
          AppButton(label: 'Issue Challan', icon: Icons.check_circle_outlined, onTap: _issue, isPrimary: true),
          const SizedBox(height: 8),
          AppButton(label: 'Delete', icon: Icons.delete_outline, onTap: _cancel, color: AppColors.error),
        ],
        if (status == 'ISSUED') ...[
          AppButton(label: 'Convert to Invoice', icon: Icons.swap_horiz_outlined, onTap: _convertToInvoice, isPrimary: true),
          const SizedBox(height: 8),
          AppButton(label: 'Cancel Challan', icon: Icons.cancel_outlined, onTap: _cancel, color: AppColors.error),
        ],
      ],
    );
  }
}
