import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../models/invoice.dart';
import '../../../providers/invoice_provider.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final String id;
  const InvoiceDetailScreen({super.key, required this.id});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  InvoiceModel? _invoice;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInvoice();
  }

  Future<void> _loadInvoice() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final invoice = await context.read<InvoiceProvider>().fetchInvoiceDetail(widget.id);
      setState(() { _invoice = invoice; _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null || _invoice == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text('Failed to load invoice', style: AppTypography.headlineMedium),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: _loadInvoice, child: const Text('Retry')),
          ],
        ),
      );
    }

    final inv = _invoice!;
    final balance = inv.total - inv.amountPaid;
    final invoiceStatus = _parseStatus(inv.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(inv.invoiceNumber, style: AppTypography.headlineLarge),
            const SizedBox(width: AppSpacing.md),
            AppStatusBadge(status: invoiceStatus),
            const Spacer(),
            AppButton(
              label: 'Edit',
              icon: Icons.edit,
              style: AppButtonStyle.secondary,
              onPressed: () {},
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: 'Send',
              icon: Icons.email,
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('FROM', style: AppTypography.labelMedium),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text('Apex Trading Co.', style: AppTypography.bodyMedium),
                                  Text('123 Industrial Area, Pune', style: AppTypography.bodySmall),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('BILL TO', style: AppTypography.labelMedium),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(inv.contactName ?? 'Unknown', style: AppTypography.bodyMedium),
                                  if (inv.contact?.phone != null)
                                    Text(inv.contact!.phone!, style: AppTypography.bodySmall),
                                  if (inv.contact?.gstin != null)
                                    Text('GSTIN: ${inv.contact!.gstin}', style: AppTypography.bodySmall),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sectionGap),

                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const AppSectionHeader(title: 'LINE ITEMS'),
                            const SizedBox(height: AppSpacing.lg),
                            if (inv.lines.isEmpty)
                              AppEmptyState(icon: Icons.list, title: 'No line items')
                            else
                              ...inv.lines.map((line) => Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(line.productName ?? 'Product', style: AppTypography.labelLarge),
                                          Text(
                                            '${line.quantity.toStringAsFixed(1)} × ₹${line.rate.toStringAsFixed(2)}',
                                            style: AppTypography.bodySmall.copyWith(color: AppColors.gray500),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Text('${line.gstRate.toStringAsFixed(0)}%', style: AppTypography.bodySmall),
                                    ),
                                    Expanded(
                                      child: Text(
                                        '₹${line.discount.toStringAsFixed(0)}',
                                        style: AppTypography.bodySmall,
                                        textAlign: TextAlign.end,
                                      ),
                                    ),
                                    Expanded(
                                      child: AppAmountText(amount: line.total, style: AppTypography.amountTiny),
                                    ),
                                  ],
                                ),
                              )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sectionGap),

              SizedBox(
                width: 280,
                child: Column(
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PAYMENT STATUS', style: AppTypography.labelMedium),
                          const SizedBox(height: AppSpacing.lg),
                          _buildSummaryRow('Total', inv.total),
                          const SizedBox(height: AppSpacing.sm),
                          _buildSummaryRow('Paid', inv.amountPaid),
                          const Divider(height: AppSpacing.xl),
                          _buildSummaryRow('Balance Due', balance, isBold: true),
                          const SizedBox(height: AppSpacing.lg),
                          AppButton(
                            label: 'Record Payment',
                            icon: Icons.payments,
                            onPressed: balance > 0 ? () {} : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sectionGap),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppSectionHeader(title: 'TOTALS'),
                          const SizedBox(height: AppSpacing.lg),
                          _buildSummaryRow('Subtotal', inv.subtotal),
                          if (inv.discountTotal > 0) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _buildSummaryRow('Discount', -inv.discountTotal),
                          ],
                          if (inv.cgstAmount > 0) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _buildSummaryRow('CGST', inv.cgstAmount),
                          ],
                          if (inv.sgstAmount > 0) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _buildSummaryRow('SGST', inv.sgstAmount),
                          ],
                          if (inv.igstAmount > 0) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _buildSummaryRow('IGST', inv.igstAmount),
                          ],
                          if (inv.roundOff != 0) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _buildSummaryRow('Round Off', inv.roundOff),
                          ],
                          const Divider(height: AppSpacing.xl),
                          _buildSummaryRow('TOTAL', inv.total, isBold: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sectionGap),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppSectionHeader(title: 'DETAILS'),
                          const SizedBox(height: AppSpacing.md),
                          _buildInfoRow('Issue Date', _formatDate(inv.issueDate)),
                          const SizedBox(height: AppSpacing.sm),
                          _buildInfoRow('Due Date', _formatDate(inv.dueDate)),
                          const SizedBox(height: AppSpacing.sm),
                          _buildInfoRow('Status', inv.status),
                          if (inv.eInvoiceStatus != 'PENDING') ...[
                            const SizedBox(height: AppSpacing.sm),
                            _buildInfoRow('E-Invoice', inv.eInvoiceStatus),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: isBold ? AppTypography.labelLarge : AppTypography.bodySmall),
        AppAmountText(
          amount: amount,
          style: isBold ? AppTypography.amountSmall : AppTypography.amountTiny,
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodySmall),
        Text(value, style: AppTypography.labelMedium),
      ],
    );
  }

  InvoiceStatus _parseStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PAID': return InvoiceStatus.paid;
      case 'PARTIAL': return InvoiceStatus.partial;
      case 'OVERDUE': return InvoiceStatus.overdue;
      case 'DRAFT': return InvoiceStatus.draft;
      case 'CANCELLED': return InvoiceStatus.cancelled;
      default: return InvoiceStatus.pending;
    }
  }

  String _formatDate(String date) {
    if (date.isEmpty) return '-';
    try {
      final d = DateTime.parse(date);
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return date;
    }
  }
}
