import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/download/download_service.dart';
import 'package:apexbooks/core/widgets/transaction_detail_layout.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/permissions/permissions.dart';
import '../models/invoice.dart';
import '../models/invoice_line.dart';
import '../models/invoice_status.dart';
import '../services/invoice_service.dart';
import 'invoice_form_notifier.dart';
import '../payments/presentation/payment_form_screen.dart';

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  final String invoiceId;
  @override
  ConsumerState<InvoiceDetailScreen> createState() =>
      _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  bool _operating = false;

  Future<void> _act(Future<Result<Invoice>> Function() call) async {
    setState(() => _operating = true);
    final res = await call();
    if (!mounted) return;
    setState(() => _operating = false);
    switch (res) {
      case Success():
        ref.invalidate(invoiceDetailProvider(widget.invoiceId));
      case Failure(:final error):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${error.message}')));
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncVal = ref.watch(invoiceDetailProvider(widget.invoiceId));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final service = ref.watch(invoiceServiceProvider);

    return asyncVal.when(
      loading: () => const Column(
        children: [
          DetailSectionSkeleton(),
          DetailSectionSkeleton(),
          DetailSectionSkeleton(),
        ],
      ),
      error: (err, _) => ErrorView(
        message: err.toString(),
        onRetry: () => ref.invalidate(invoiceDetailProvider(widget.invoiceId)),
      ),
      data: (inv) => TransactionDetailLayout(
        title: inv.invoiceNumber,
        header: _summaryCard(inv, colors, fmt),
        lines: _linesCard(inv, colors, fmt),
        totals: _totalsCard(inv, colors, fmt),
        actions: _buildActions(inv, service, colors),
        notes:
            (inv.notes ?? '').isNotEmpty ||
                (inv.termsAndConditions ?? '').isNotEmpty
            ? _notesCard(inv, colors)
            : null,
      ),
    );
  }

  Future<void> _printInvoice(Invoice inv) async {
    final downloadSvc = ref.read(downloadServiceProvider);
    final result = await downloadSvc.download(
      relativeUrl: '/invoices/${inv.id}/print',
      filename: inv.invoiceNumber,
      kind: ExportKind.pdf,
    );
    if (!mounted) return;
    switch (result) {
      case Success():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded ${inv.invoiceNumber}.pdf'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case Failure(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${error.message}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      default:
        break;
    }
  }

  Future<void> _emailInvoice(Invoice inv, InvoiceService service) async {
    setState(() => _operating = true);
    final result = await service.email(inv.id);
    if (!mounted) return;
    setState(() => _operating = false);
    final message = result is Success<void>
        ? 'Invoice queued for email delivery.'
        : 'Unable to email invoice: ${(result as Failure<void>).error.message}';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _receivePayment(Invoice inv) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentFormScreen(
          contactId: inv.contactId,
          contactName: inv.contactName,
          amount: inv.outstanding.toDouble(),
        ),
      ),
    );
    ref.invalidate(invoiceDetailProvider(widget.invoiceId));
  }

  // ── Action buttons for the AppBar ──────────────────────────────────────────
  List<Widget> _buildActions(
    Invoice inv,
    InvoiceService service,
    ApexColors colors,
  ) {
    return [
      OutlinedButton.icon(
        onPressed: () => _printInvoice(inv),
        icon: const Icon(Icons.print_rounded, size: 18),
        label: const Text('Print'),
      ),
      if (inv.status != InvoiceStatus.draft &&
          inv.status != InvoiceStatus.cancelled)
        PermissionGate(
          permission: Permissions.invoiceEmail,
          child: OutlinedButton.icon(
            onPressed: _operating ? null : () => _emailInvoice(inv, service),
            icon: const Icon(Icons.email_outlined, size: 18),
            label: const Text('Email'),
          ),
        ),
      if (inv.outstanding > 0 &&
          (inv.status == InvoiceStatus.posted ||
              inv.status == InvoiceStatus.sent ||
              inv.status == InvoiceStatus.partiallyPaid))
        FilledButton.icon(
          onPressed: _operating ? null : () => _receivePayment(inv),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('Receive payment'),
        ),
      StatusBadge(
        label: inv.status.value.replaceAll('_', ' '),
        tone: toneForStatus(inv.status.value),
      ),
      if (_operating) const LoadingSpinner(size: 18),
      if (inv.status == InvoiceStatus.draft)
        FilledButton.icon(
          onPressed: _operating
              ? null
              : () => _act(() => service.finalize(inv.id)),
          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: const Text('Finalize'),
        ),
      if (inv.status == InvoiceStatus.posted ||
          inv.status == InvoiceStatus.paid)
        PermissionGate(
          permission: Permissions.invoiceCancel,
          child: OutlinedButton.icon(
            onPressed: _operating
                ? null
                : () => _act(() => service.cancel(inv.id)),
            icon: Icon(Icons.cancel_outlined, size: 18, color: colors.danger),
            label: Text('Cancel', style: TextStyle(color: colors.danger)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colors.danger.withValues(alpha: 0.4)),
            ),
          ),
        ),
    ];
  }

  // ── Bill-to + meta ────────────────────────────────────────────────────────
  Widget _summaryCard(Invoice inv, ApexColors colors, NumberFormatter fmt) {
    final balance = (inv.total - inv.amountPaid)
        .clamp(0, double.infinity)
        .toDouble();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BILL TO', style: _label(colors)),
              const SizedBox(height: 4),
              Text(
                inv.contactName ?? '—',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Place of supply: ${inv.posStateCode.isEmpty ? '—' : inv.posStateCode}',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
              if ((inv.referenceNumber ?? '').isNotEmpty)
                Text(
                  'Ref: ${inv.referenceNumber}',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _metaRow('Issued', inv.issueDate, colors),
            const SizedBox(height: 6),
            _metaRow('Due', inv.dueDate, colors),
            const SizedBox(height: 10),
            Text('BALANCE DUE', style: _label(colors)),
            Text(
              fmt.currency(balance),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: balance > 0 ? colors.danger : colors.success,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metaRow(String label, String value, ApexColors colors) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label  ', style: TextStyle(fontSize: 12, color: colors.textMuted)),
      Text(
        value.isEmpty ? '—' : value,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
    ],
  );

  // ── Line items table ──────────────────────────────────────────────────────
  Widget _linesCard(Invoice inv, ApexColors colors, NumberFormatter fmt) {
    final lineTable = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ApexRadius.lg),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(flex: 40, child: Text('ITEM', style: _th(colors))),
              Expanded(
                flex: 12,
                child: Text(
                  'QTY',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 18,
                child: Text(
                  'RATE',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 12,
                child: Text(
                  'GST',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 18,
                child: Text(
                  'AMOUNT',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
            ],
          ),
        ),
        ...inv.lines.asMap().entries.map(
          (e) => _lineRow(e.value, e.key == inv.lines.length - 1, colors, fmt),
        ),
      ],
    );
    final isMobile = ResponsiveLayout.isMobile(context);
    return isMobile
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: lineTable,
          )
        : lineTable;
  }

  Widget _lineRow(
    InvoiceLine l,
    bool last,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.productName ?? l.description ?? 'Item',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                if (l.hsnSac.isNotEmpty)
                  Text(
                    'HSN ${l.hsnSac}',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 12,
            child: Text(
              fmt.quantity(l.quantity),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
          Expanded(
            flex: 18,
            child: Text(
              fmt.currency(l.rate),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
          Expanded(
            flex: 12,
            child: Text(
              '${l.gstRate.toInt()}%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
          Expanded(
            flex: 18,
            child: Text(
              fmt.currency(l.total),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Totals ────────────────────────────────────────────────────────────────
  Widget _totalsCard(Invoice inv, ApexColors colors, NumberFormatter fmt) {
    final tax =
        inv.cgstAmount +
        inv.sgstAmount +
        inv.igstAmount +
        inv.utgstAmount +
        inv.cessAmount;
    final isDesktop = !ResponsiveLayout.isMobile(context);
    return Row(
      children: [
        if (isDesktop) const Spacer(),
        SizedBox(
          width: isDesktop ? 340 : double.infinity,
          child: ApexCard(
            child: Column(
              children: [
                _totRow('Subtotal', fmt.currency(inv.subtotal), colors),
                if (inv.discountTotal != 0)
                  _totRow(
                    'Discount',
                    '- ${fmt.currency(inv.discountTotal)}',
                    colors,
                  ),
                if (inv.cgstAmount != 0)
                  _totRow('CGST', fmt.currency(inv.cgstAmount), colors),
                if (inv.sgstAmount != 0)
                  _totRow('SGST', fmt.currency(inv.sgstAmount), colors),
                if (inv.igstAmount != 0)
                  _totRow('IGST', fmt.currency(inv.igstAmount), colors),
                if (inv.cessAmount != 0)
                  _totRow('Cess', fmt.currency(inv.cessAmount), colors),
                if (tax != 0 && inv.igstAmount == 0 && inv.cgstAmount == 0)
                  _totRow('Tax', fmt.currency(tax), colors),
                if (inv.shippingCharges != 0)
                  _totRow(
                    'Shipping',
                    fmt.currency(inv.shippingCharges),
                    colors,
                  ),
                if (inv.roundOff != 0)
                  _totRow('Round off', fmt.currency(inv.roundOff), colors),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, color: colors.border),
                ),
                _totRow(
                  'Total',
                  fmt.currency(inv.total),
                  colors,
                  emphasize: true,
                ),
                if (inv.amountPaid != 0)
                  _totRow(
                    'Paid',
                    '- ${fmt.currency(inv.amountPaid)}',
                    colors,
                    tone: colors.success,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _totRow(
    String label,
    String value,
    ApexColors colors, {
    bool emphasize = false,
    Color? tone,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: emphasize ? 14 : 12.5,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            color: emphasize ? colors.textPrimary : colors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasize ? 16 : 13,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            color: tone ?? (emphasize ? colors.primary : colors.textPrimary),
          ),
        ),
      ],
    ),
  );

  Widget _notesCard(Invoice inv, ApexColors colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if ((inv.notes ?? '').isNotEmpty) ...[
        Text('NOTES', style: _label(colors)),
        const SizedBox(height: 4),
        Text(
          inv.notes!,
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),
      ],
      if ((inv.notes ?? '').isNotEmpty &&
          (inv.termsAndConditions ?? '').isNotEmpty)
        const SizedBox(height: 12),
      if ((inv.termsAndConditions ?? '').isNotEmpty) ...[
        Text('TERMS', style: _label(colors)),
        const SizedBox(height: 4),
        Text(
          inv.termsAndConditions!,
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),
      ],
    ],
  );

  TextStyle _label(ApexColors colors) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    color: colors.textMuted,
  );
  TextStyle _th(ApexColors colors) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: colors.textMuted,
  );
}
