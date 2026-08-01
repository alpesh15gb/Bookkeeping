import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/download/download_service.dart';
import 'package:apexbooks/features/offline_repository_providers.dart';
import 'package:apexbooks/features/purchases/vendor_bills/models/bill_status.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../models/vendor_bill.dart';
import '../models/bill_line.dart';
import '../services/vendor_bill_service.dart';

final billDetailProvider = FutureProvider.autoDispose
    .family<VendorBill, String>((ref, id) async {
      final repo = ref.watch(purchasingRepositoryProvider);
      final pi = await repo.getPurchaseInvoice(id);
      if (pi == null) throw Exception('Bill not found locally');
      return VendorBill(
        id: pi.localId,
        billNumber: pi.invoiceNumber,
        contactId: pi.supplierId,
        contactName: pi.supplierName,
        issueDate: pi.invoiceDate,
        dueDate: pi.invoiceDate,
        status: BillStatus.fromString(pi.lifecycleStatus),
        subtotal: pi.totalBeforeTaxPaise / 100.0,
        discountTotal: 0,
        cgstAmount: pi.taxPaise / 200.0,
        sgstAmount: pi.taxPaise / 200.0,
        igstAmount: 0,
        utgstAmount: 0,
        cessAmount: 0,
        roundOff: 0,
        total: pi.totalPaise / 100.0,
        amountPaid: 0,
        posStateCode: '',
        referenceNumber: pi.referenceNumber,
        notes: pi.description,
        lines: pi.lines.map((l) {
          return BillLine(
            id: l.localId,
            productName: l.productName,
            description: l.description,
            quantity: double.tryParse(l.quantity) ?? 0,
            rate: l.unitPricePaise / 100.0,
            total: l.totalPaise / 100.0,
          );
        }).toList(),
      );
    });

class BillDetailScreen extends ConsumerStatefulWidget {
  const BillDetailScreen({super.key, required this.billId});
  final String billId;
  @override
  ConsumerState<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends ConsumerState<BillDetailScreen> {
  bool _operating = false;

  Future<void> _act(Future<Result<VendorBill>> Function() call) async {
    setState(() => _operating = true);
    final res = await call();
    if (!mounted) return;
    setState(() => _operating = false);
    switch (res) {
      case Success():
        ref.invalidate(billDetailProvider(widget.billId));
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
    final asyncVal = ref.watch(billDetailProvider(widget.billId));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final service = ref.watch(vendorBillServiceProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: asyncVal.when(
        loading: () => const Center(child: LoadingSpinner(size: 32)),
        error: (err, _) => ErrorView(
          message: userFacingErrorMessage(err),
          onRetry: () => ref.invalidate(billDetailProvider(widget.billId)),
        ),
        data: (bill) => Column(
          children: [
            _actionBar(bill, service, colors),
            Expanded(
              child: Scrollbar(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _summaryCard(bill, colors, fmt),
                    const SizedBox(height: 16),
                    _linesCard(bill, colors, fmt),
                    const SizedBox(height: 16),
                    _totalsCard(bill, colors, fmt),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printBill(VendorBill bill) async {
    final downloadSvc = ref.read(downloadServiceProvider);
    final result = await downloadSvc.download(
      relativeUrl: '/bills/${bill.id}/print',
      filename: bill.billNumber,
      kind: ExportKind.pdf,
    );
    if (!mounted) return;
    switch (result) {
      case Success():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded ${bill.billNumber}.pdf'),
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

  Widget _actionBar(
    VendorBill bill,
    VendorBillService service,
    ApexColors colors,
  ) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final title = bill.billNumber.isNotEmpty ? bill.billNumber : 'Vendor Bill';
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
                        title,
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
                      label: bill.status.value.replaceAll('_', ' '),
                      tone: toneForStatus(bill.status.value),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _printBill(bill),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Print'),
                    ),
                    if (_operating) const LoadingSpinner(size: 18),
                    if (bill.status.name == 'draft')
                      FilledButton.icon(
                        onPressed: _operating
                            ? null
                            : () => _act(() => service.post(bill.id)),
                        icon: const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Post Bill'),
                      ),
                    if (bill.status.name == 'posted')
                      OutlinedButton.icon(
                        onPressed: _operating
                            ? null
                            : () => _act(() => service.cancel(bill.id)),
                        icon: Icon(
                          Icons.cancel_outlined,
                          size: 18,
                          color: colors.danger,
                        ),
                        label: Text(
                          'Cancel',
                          style: TextStyle(color: colors.danger),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: colors.danger.withValues(alpha: 0.4),
                          ),
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
                          title,
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
                        label: bill.status.value.replaceAll('_', ' '),
                        tone: toneForStatus(bill.status.value),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _printBill(bill),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('Print'),
                ),
                const SizedBox(width: 8),
                if (_operating)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: LoadingSpinner(size: 18),
                  ),
                if (bill.status.name == 'draft')
                  FilledButton.icon(
                    onPressed: _operating
                        ? null
                        : () => _act(() => service.post(bill.id)),
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
                    label: const Text('Post Bill'),
                  ),
                if (bill.status.name == 'posted') ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _operating
                        ? null
                        : () => _act(() => service.cancel(bill.id)),
                    icon: Icon(
                      Icons.cancel_outlined,
                      size: 18,
                      color: colors.danger,
                    ),
                    label: Text(
                      'Cancel',
                      style: TextStyle(color: colors.danger),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: colors.danger.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _summaryCard(VendorBill bill, ApexColors colors, NumberFormatter fmt) {
    final balance = (bill.total - bill.amountPaid)
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
                Text('VENDOR', style: _label(colors)),
                const SizedBox(height: 4),
                Text(
                  bill.contactName ?? '—',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'POS state: ${bill.posStateCode.isEmpty ? '—' : bill.posStateCode}',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
                if ((bill.referenceNumber ?? '').isNotEmpty)
                  Text(
                    'Ref: ${bill.referenceNumber}',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _metaRow('Issued', bill.issueDate, colors),
              const SizedBox(height: 6),
              _metaRow('Due', bill.dueDate, colors),
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

  Widget _linesCard(VendorBill bill, ApexColors colors, NumberFormatter fmt) {
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
        ...bill.lines.asMap().entries.map(
          (e) => _lineRow(e.value, e.key == bill.lines.length - 1, colors, fmt),
        ),
      ],
    );
    return _Panel(
      colors: colors,
      padding: EdgeInsets.zero,
      child: ResponsiveLayout.isMobile(context)
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: lineTable,
            )
          : lineTable,
    );
  }

  Widget _lineRow(
    BillLine l,
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

  Widget _totalsCard(VendorBill bill, ApexColors colors, NumberFormatter fmt) {
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
                _totRow('Subtotal', fmt.currency(bill.subtotal), colors),
                if (bill.discountTotal != 0)
                  _totRow(
                    'Discount',
                    '- ${fmt.currency(bill.discountTotal)}',
                    colors,
                  ),
                if (bill.cgstAmount != 0)
                  _totRow('CGST', fmt.currency(bill.cgstAmount), colors),
                if (bill.sgstAmount != 0)
                  _totRow('SGST', fmt.currency(bill.sgstAmount), colors),
                if (bill.igstAmount != 0)
                  _totRow('IGST', fmt.currency(bill.igstAmount), colors),
                if (bill.cessAmount != 0)
                  _totRow('Cess', fmt.currency(bill.cessAmount), colors),
                if (bill.roundOff != 0)
                  _totRow('Round off', fmt.currency(bill.roundOff), colors),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, color: colors.border),
                ),
                _totRow(
                  'Total',
                  fmt.currency(bill.total),
                  colors,
                  emphasize: true,
                ),
                if (bill.amountPaid != 0)
                  _totRow(
                    'Paid',
                    '- ${fmt.currency(bill.amountPaid)}',
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
  const _Panel({required this.colors, required this.child, this.padding});
  final ApexColors colors;
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) =>
      ApexCard(padding: padding ?? const EdgeInsets.all(18), child: child);
}
