import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_line.dart';
import '../models/purchase_order_status.dart';
import '../services/purchase_order_service.dart';

final purchaseOrderDetailProvider = FutureProvider.autoDispose
    .family<PurchaseOrder, String>((ref, id) async {
      final res = await ref.watch(purchaseOrderServiceProvider).get(id);
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });

class PurchaseOrderDetailScreen extends ConsumerStatefulWidget {
  const PurchaseOrderDetailScreen({super.key, required this.poId});
  final String poId;
  @override
  ConsumerState<PurchaseOrderDetailScreen> createState() =>
      _PurchaseOrderDetailScreenState();
}

class _PurchaseOrderDetailScreenState
    extends ConsumerState<PurchaseOrderDetailScreen> {
  bool _operating = false;

  Future<void> _act(Future<Result<PurchaseOrder>> Function() call) async {
    setState(() => _operating = true);
    final res = await call();
    if (!mounted) return;
    setState(() => _operating = false);
    switch (res) {
      case Success():
        ref.invalidate(purchaseOrderDetailProvider(widget.poId));
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
    final asyncVal = ref.watch(purchaseOrderDetailProvider(widget.poId));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final service = ref.watch(purchaseOrderServiceProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: asyncVal.when(
        loading: () => const Center(child: LoadingSpinner(size: 32)),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () =>
              ref.invalidate(purchaseOrderDetailProvider(widget.poId)),
        ),
        data: (po) => Column(
          children: [
            _actionBar(po, service, colors),
            Expanded(
              child: Scrollbar(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _summaryCard(po, colors, fmt),
                    const SizedBox(height: 16),
                    _linesCard(po, colors, fmt),
                    const SizedBox(height: 16),
                    _totalsCard(po, colors, fmt),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printPo(PurchaseOrder po) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading ${po.poNumber}.pdf...'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _actionBar(
    PurchaseOrder po,
    PurchaseOrderService service,
    ApexColors colors,
  ) {
    final title = po.poNumber.isNotEmpty ? po.poNumber : 'Purchase Order';
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: ResponsiveLayout.isMobile(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      label: po.status.value,
                      tone: _tone(po.status),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _printPo(po),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Print'),
                    ),
                    if (_operating)
                      const LoadingSpinner(size: 18),
                    if (po.status == PurchaseOrderStatus.draft)
                      FilledButton.icon(
                        onPressed: _operating
                            ? null
                            : () => _act(() => service.confirm(po.id)),
                        icon: const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Confirm'),
                      ),
                    if (po.status.isCancellable)
                      OutlinedButton.icon(
                        onPressed: _operating
                            ? null
                            : () => _act(() => service.cancel(po.id)),
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
                        label: po.status.value,
                        tone: _tone(po.status),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _printPo(po),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('Print'),
                ),
                const SizedBox(width: 8),
                if (_operating)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: LoadingSpinner(size: 18),
                  ),
                if (po.status == PurchaseOrderStatus.draft)
                  FilledButton.icon(
                    onPressed: _operating
                        ? null
                        : () => _act(() => service.confirm(po.id)),
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
                    label: const Text('Confirm'),
                  ),
                if (po.status.isCancellable) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _operating
                        ? null
                        : () => _act(() => service.cancel(po.id)),
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

  Widget _summaryCard(
    PurchaseOrder po,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
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
                  po.contactName ?? '—',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'POS state: ${po.posStateCode.isEmpty ? '—' : po.posStateCode}',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _metaRow('Ordered', po.orderDate, colors),
              const SizedBox(height: 6),
              _metaRow('Due', po.dueDate, colors),
              const SizedBox(height: 10),
              Text('ORDER TOTAL', style: _label(colors)),
              Text(
                fmt.currency(po.total),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
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

  Widget _linesCard(PurchaseOrder po, ApexColors colors, NumberFormatter fmt) {
    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
              Expanded(flex: 36, child: Text('ITEM', style: _th(colors))),
              Expanded(
                flex: 14,
                child: Text(
                  'ORDERED',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 14,
                child: Text(
                  'RECEIVED',
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
        ...po.lines.asMap().entries.map(
          (e) => _lineRow(e.value, e.key == po.lines.length - 1, colors, fmt),
        ),
      ],
    );

    return _Panel(
      colors: colors,
      padding: EdgeInsets.zero,
      child: ResponsiveLayout.isMobile(context)
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: table,
            )
          : table,
    );
  }

  Widget _lineRow(
    PurchaseOrderLine l,
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
            flex: 36,
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
            flex: 14,
            child: Text(
              fmt.quantity(l.quantity),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
          Expanded(
            flex: 14,
            child: Text(
              fmt.quantity(l.quantityReceived),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: l.isFullyReceived
                    ? colors.success
                    : (l.quantityReceived > 0
                          ? colors.warning
                          : colors.textMuted),
              ),
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

  Widget _totalsCard(PurchaseOrder po, ApexColors colors, NumberFormatter fmt) {
    return Row(
      children: [
        const Spacer(),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveLayout.isMobile(context) ? double.infinity : 340,
          ),
          child: _Panel(
            colors: colors,
            child: Column(
              children: [
                _totRow('Subtotal', fmt.currency(po.subtotal), colors),
                if (po.discountTotal != 0)
                  _totRow(
                    'Discount',
                    '- ${fmt.currency(po.discountTotal)}',
                    colors,
                  ),
                if (po.cgstAmount != 0)
                  _totRow('CGST', fmt.currency(po.cgstAmount), colors),
                if (po.sgstAmount != 0)
                  _totRow('SGST', fmt.currency(po.sgstAmount), colors),
                if (po.igstAmount != 0)
                  _totRow('IGST', fmt.currency(po.igstAmount), colors),
                if (po.cessAmount != 0)
                  _totRow('Cess', fmt.currency(po.cessAmount), colors),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, color: colors.border),
                ),
                _totRow(
                  'Total',
                  fmt.currency(po.total),
                  colors,
                  emphasize: true,
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
            color: emphasize ? colors.primary : colors.textPrimary,
          ),
        ),
      ],
    ),
  );

  StatusTone _tone(PurchaseOrderStatus s) => switch (s) {
    PurchaseOrderStatus.draft => StatusTone.neutral,
    PurchaseOrderStatus.confirmed => StatusTone.primary,
    PurchaseOrderStatus.received => StatusTone.success,
    PurchaseOrderStatus.cancelled => StatusTone.danger,
  };

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
