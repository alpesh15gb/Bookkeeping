import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/invoice.dart';
import '../models/invoice_line.dart';
import '../models/invoice_status.dart';
import '../services/invoice_service.dart';
import 'invoice_form_notifier.dart';

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

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: asyncVal.when(
        loading: () => const Column(
          children: [
            DetailSectionSkeleton(),
            DetailSectionSkeleton(),
            DetailSectionSkeleton(),
          ],
        ),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () =>
              ref.invalidate(invoiceDetailProvider(widget.invoiceId)),
        ),
        data: (inv) => Column(
          children: [
            _actionBar(inv, service, colors),
            Expanded(
              child: Scrollbar(
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: 5,
                  itemBuilder: (context, index) {
                    switch (index) {
                      case 0:
                        return _summaryCard(inv, colors, fmt);
                      case 1:
                        return const SizedBox(height: 16);
                      case 2:
                        return _linesCard(inv, colors, fmt);
                      case 3:
                        return Column(
                          children: [
                            const SizedBox(height: 16),
                            _totalsCard(inv, colors, fmt),
                            if ((inv.notes ?? '').isNotEmpty ||
                                (inv.termsAndConditions ?? '').isNotEmpty)
                              const SizedBox(height: 16),
                          ],
                        );
                      case 4:
                        if ((inv.notes ?? '').isNotEmpty ||
                            (inv.termsAndConditions ?? '').isNotEmpty) {
                          return _notesCard(inv, colors);
                        }
                        return const SizedBox.shrink();
                      default:
                        return const SizedBox.shrink();
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sticky action bar ─────────────────────────────────────────────────────
  Widget _actionBar(Invoice inv, InvoiceService service, ApexColors colors) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        inv.invoiceNumber,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    StatusBadge(
                      label: inv.status.value.replaceAll('_', ' '),
                      tone: toneForStatus(inv.status.value),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_operating)
                      const LoadingSpinner(size: 18),
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
                      OutlinedButton.icon(
                        onPressed: _operating
                            ? null
                            : () => _act(() => service.cancel(inv.id)),
                        icon: Icon(Icons.cancel_outlined, size: 18, color: colors.danger),
                        label: Text('Cancel', style: TextStyle(color: colors.danger)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.danger.withValues(alpha: 0.4)),
                        ),
                      ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          inv.invoiceNumber,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      StatusBadge(
                        label: inv.status.value.replaceAll('_', ' '),
                        tone: toneForStatus(inv.status.value),
                      ),
                    ],
                  ),
                ),
                if (_operating)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: LoadingSpinner(size: 18),
                  ),
                if (inv.status == InvoiceStatus.draft)
                  FilledButton.icon(
                    onPressed: _operating
                        ? null
                        : () => _act(() => service.finalize(inv.id)),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: const Text('Finalize'),
                  ),
                if (inv.status == InvoiceStatus.posted ||
                    inv.status == InvoiceStatus.paid) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _operating
                        ? null
                        : () => _act(() => service.cancel(inv.id)),
                    icon: Icon(Icons.cancel_outlined, size: 18, color: colors.danger),
                    label: Text('Cancel', style: TextStyle(color: colors.danger)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.danger.withValues(alpha: 0.4)),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  // ── Bill-to + meta ────────────────────────────────────────────────────────
  Widget _summaryCard(Invoice inv, ApexColors colors, NumberFormatter fmt) {
    final balance = (inv.total - inv.amountPaid)
        .clamp(0, double.infinity)
        .toDouble();
    return _Panel(
      colors: colors,
      child: Row(
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
      ),
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
          (e) =>
              _lineRow(e.value, e.key == inv.lines.length - 1, colors, fmt),
        ),
      ],
    );
    final isMobile = ResponsiveLayout.isMobile(context);
    return _Panel(
      colors: colors,
      padding: EdgeInsets.zero,
      child: isMobile
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: lineTable,
            )
          : lineTable,
    );
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
          child: _Panel(
            colors: colors,
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

  Widget _notesCard(Invoice inv, ApexColors colors) => _Panel(
    colors: colors,
    child: Column(
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
    ),
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

class _Panel extends StatelessWidget {
  const _Panel({
    required this.colors,
    required this.child,
    this.padding,
  });
  final ApexColors colors;
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) =>
      ApexCard(padding: padding ?? const EdgeInsets.all(18), child: child);
}
