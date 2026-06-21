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
                  : _buildEnhancedTable(_showReceipts ? receipts : disbursements, _showReceipts),
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
  Widget _buildEnhancedTable(List<dynamic> items, bool isReceipts) {
    final rows = items.map((p) {
      final statusParsed = p.status == 'COMPLETED' ? InvoiceStatus.paid : InvoiceStatus.pending;
      return <String, dynamic>{
        'payment_date': _formatDate(p.paymentDate),
        'contact_name': isReceipts ? p.contactName : p.vendorName,
        'payment_mode': p.paymentMode,
        'reference_number': p.referenceNumber ?? '-',
        'amount': p.amount,
        'status': p.status,
        '_parseStatus': statusParsed,
      };
    }).toList();

    final totalAmount = rows.fold<double>(0, (sum, row) => sum + row['amount'] as double);

    return AppTable(
      title: '${rows.length} payment${rows.length == 1 ? '' : 's'} ' + (isReceipts ? 'received' : 'made'),
      columns: const [
        AppTableColumn(label: 'Date', width: 110, fieldKey: 'payment_date', isSortable: true),
        AppTableColumn(label: isReceipts ? 'Customer' : 'Vendor', width: 200, fieldKey: 'contact_name', isSortable: true),
        AppTableColumn(label: 'Mode', width: 120, fieldKey: 'payment_mode'),
        AppTableColumn(label: 'Reference', width: 140, fieldKey: 'reference_number'),
        AppTableColumn(label: 'Amount', width: 120, fieldKey: 'amount', alignment: Alignment.centerRight, isSortable: true),
        AppTableColumn(label: 'Status', width: 100, fieldKey: 'status', alignment: Alignment.center, isSortable: true),
      ],
      rows: rows,
      stickyHeader: true,
      stickyFooter: true,
      density: AppTableDensity.comfortable,
      enableKeyboardNav: true,
      enableColumnChooser: true,
      enableExport: true,
      summaryRows: [
        {
          'payment_date': 'TOTALS',
          'contact_name': '',
          'payment_mode': '',
          'reference_number': '',
          'amount': totalAmount,
          'status': '',
        },
      ],
    );
  }
