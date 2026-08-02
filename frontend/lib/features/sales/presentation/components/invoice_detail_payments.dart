/// Invoice Detail Payments — Payment allocation history with add payment action.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/permissions/permissions.dart';
import '../../models/invoice.dart';
import '../../models/invoice_status.dart';
import '../../payments/models/payment_models.dart';
import '../../payments/models/payment_enums.dart';
import '../../payments/presentation/payment_form_screen.dart';
import '../invoice_detail_screen.dart';

class InvoiceDetailPayments extends ConsumerWidget {
  const InvoiceDetailPayments({super.key, required this.invoice, required this.fmt});

  final Invoice invoice;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);
    final payments = invoice.payments;

    return Column(
      children: [
        // Header with Add Payment button
        Container(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Text('Payments (${payments.length})', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (invoice.outstandingAmount > 0 && invoice.status != InvoiceStatus.cancelled)
                PermissionGate(
                  permission: Permissions.paymentCreate,
                  child: ApexPrimaryButton(
                    icon: Icons.add,
                    label: 'Record Payment',
                    onPressed: () => _openPaymentForm(context, ref),
                  ),
                ),
            ],
          ),
        ),

        // Content
        if (payments.isEmpty)
          _buildEmptyState(context)
        else
          Expanded(child: _buildPaymentsList(context, payments, isMobile)),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    return Expanded(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 24 : 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 48, color: colors.textMuted),
              const SizedBox(height: 12),
              Text('No Payments Recorded', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
              const SizedBox(height: 4),
              Text('Record payments to track outstanding amounts', style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentsList(BuildContext context, List<Payment> payments, bool isMobile) {
    final colors = apexColors(context);

    if (isMobile) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: payments.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildPaymentCard(context, payments[index]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: payments.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: colors.border),
      itemBuilder: (context, index) => _buildPaymentRow(context, payments[index], index),
    );
  }

  Widget _buildPaymentCard(BuildContext context, Payment payment) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return ApexCard(
      elevation: CardElevation.low,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getMethodColor(payment.paymentMode).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_getMethodIcon(payment.paymentMode), size: 14, color: _getMethodColor(payment.paymentMode)),
                    const SizedBox(width: 4),
                    Text(_formatMethod(payment.paymentMode), style: textTheme.labelSmall?.copyWith(color: _getMethodColor(payment.paymentMode), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const Spacer(),
              Text(fmt.currency(payment.amount), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: colors.success, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _paymentInfoItem(context, label: 'Date', value: _formatDate(payment.paymentDate), icon: Icons.calendar_today)),
              Expanded(child: _paymentInfoItem(context, label: 'Reference', value: payment.referenceNumber ?? '—', icon: Icons.receipt)),
            ],
          ),
          if (payment.description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(payment.description!, style: textTheme.bodySmall?.copyWith(color: colors.textSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentRow(BuildContext context, Payment payment, int index) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      color: index.isEven ? colors.surface : colors.surfaceMuted.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Method
          Container(
            width: 140,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getMethodColor(payment.paymentMode).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_getMethodIcon(payment.paymentMode), size: 14, color: _getMethodColor(payment.paymentMode)),
                const SizedBox(width: 6),
                Text(_formatMethod(payment.paymentMode), style: textTheme.labelMedium?.copyWith(color: _getMethodColor(payment.paymentMode), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Date
          SizedBox(
            width: 120,
            child: Text(_formatDate(payment.paymentDate), style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(width: 16),
          // Reference
          Expanded(
            child: Text(payment.referenceNumber ?? '—', style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 16),
          // Notes
          Expanded(
            child: Text(payment.description ?? '—', style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 16),
          // Amount
          SizedBox(
            width: 140,
            child: Text(
              fmt.currency(payment.amount),
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.success,
                fontFamily: 'JetBrains Mono',
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentInfoItem(BuildContext context, {required String label, required String value, required IconData icon}) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: textTheme.labelSmall?.copyWith(color: colors.textMuted)),
            Text(value, style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary)),
          ],
        ),
      ],
    );
  }

  void _openPaymentForm(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentFormScreen(
          contactId: invoice.contactId,
          amount: invoice.outstandingAmount,
        ),
      ),
    );
    if (result == true && context.mounted) {
      ref.invalidate(invoiceDetailProvider(invoice.id));
      ApexSnackBar.show(context: context, message: 'Payment recorded', type: SnackBarType.success);
    }
  }

  Color _getMethodColor(PaymentMode method) {
    switch (method) {
      case PaymentMode.cash:
        return Colors.green;
      case PaymentMode.bank:
        return Colors.blue;
      case PaymentMode.cheque:
        return Colors.orange;
      case PaymentMode.upi:
        return Colors.purple;
      case PaymentMode.pos:
        return Colors.indigo;
      case PaymentMode.neftRtgs:
        return Colors.teal;
      case PaymentMode.other:
        return Colors.grey;
    }
  }

  IconData _getMethodIcon(PaymentMode method) {
    switch (method) {
      case PaymentMode.cash:
        return Icons.money;
      case PaymentMode.bank:
        return Icons.account_balance;
      case PaymentMode.cheque:
        return Icons.receipt_long;
      case PaymentMode.upi:
        return Icons.qr_code;
      case PaymentMode.pos:
        return Icons.point_of_sale;
      case PaymentMode.neftRtgs:
        return Icons.account_balance_wallet;
      case PaymentMode.other:
        return Icons.more_horiz;
    }
  }

  String _formatMethod(PaymentMode method) {
    return method.name.toUpperCase();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}