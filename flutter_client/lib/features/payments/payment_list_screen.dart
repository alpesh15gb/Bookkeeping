import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/payment_provider.dart';

class PaymentListScreen extends StatefulWidget {
  const PaymentListScreen({super.key});

  @override
  State<PaymentListScreen> createState() => _PaymentListScreenState();
}

class _PaymentListScreenState extends State<PaymentListScreen> {
  bool _showReceipts = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final paymentProv = context.read<PaymentProvider>();
      paymentProv.fetchReceipts();
      paymentProv.fetchDisbursements();
    });
  }

  @override
  Widget build(BuildContext context) {
    final paymentProvider = context.watch<PaymentProvider>();
    final receipts = paymentProvider.receipts;
    final disbursements = paymentProvider.disbursements;
    final isLoading = paymentProvider.isLoading;

    final items = _showReceipts ? receipts : disbursements;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Payments', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Payment', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AppFilterChip(
              label: 'Received',
              count: receipts.length,
              isSelected: _showReceipts,
              selectedColor: AppColors.success,
              onTap: () => setState(() => _showReceipts = true),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'Made',
              count: disbursements.length,
              isSelected: !_showReceipts,
              selectedColor: AppColors.error,
              onTap: () => setState(() => _showReceipts = false),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? AppEmptyState(
                      icon: Icons.payments,
                      title: _showReceipts ? 'No payments received' : 'No payments made',
                    )
                  : _showReceipts
                      ? AppTable(
                          columns: const [
                            TableColumn(label: 'Date', width: 110),
                            TableColumn(label: 'Party', width: 200),
                            TableColumn(label: 'Mode', width: 120),
                            TableColumn(label: 'Reference', width: 140),
                            TableColumn(label: 'Amount', width: 120),
                            TableColumn(label: 'Status', width: 100),
                          ],
                          rows: receipts.map((p) {
                            return AppTableRow(
                              cells: [
                                Text(_formatDate(p.paymentDate), style: AppTypography.bodySmall),
                                Text(p.contactName ?? '', style: AppTypography.bodyMedium),
                                Text(p.paymentMode, style: AppTypography.bodySmall),
                                Text(p.referenceNumber ?? '-', style: AppTypography.bodySmall),
                                AppAmountText(amount: p.amount, style: AppTypography.amountTiny),
                                AppStatusBadge(
                                  status: p.status == 'COMPLETED' ? InvoiceStatus.paid : InvoiceStatus.pending,
                                  isCompact: true,
                                ),
                              ],
                            );
                          }).toList(),
                        )
                      : AppTable(
                          columns: const [
                            TableColumn(label: 'Date', width: 110),
                            TableColumn(label: 'Vendor', width: 200),
                            TableColumn(label: 'Mode', width: 120),
                            TableColumn(label: 'Reference', width: 140),
                            TableColumn(label: 'Amount', width: 120),
                            TableColumn(label: 'Status', width: 100),
                          ],
                          rows: disbursements.map((p) {
                            return AppTableRow(
                              cells: [
                                Text(_formatDate(p.paymentDate), style: AppTypography.bodySmall),
                                Text(p.vendorName ?? '', style: AppTypography.bodyMedium),
                                Text(p.paymentMode, style: AppTypography.bodySmall),
                                Text(p.referenceNumber ?? '-', style: AppTypography.bodySmall),
                                AppAmountText(amount: p.amount, style: AppTypography.amountTiny),
                                AppStatusBadge(
                                  status: p.status == 'COMPLETED' ? InvoiceStatus.paid : InvoiceStatus.pending,
                                  isCompact: true,
                                ),
                              ],
                            );
                          }).toList(),
                        ),
        ),
      ],
    );
  }

  String _formatDate(String date) {
    if (date.isEmpty) return '-';
    try {
      final d = DateTime.parse(date);
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}';
    } catch (_) {
      return date;
    }
  }
}
