import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/goods_receipt.dart';
import '../models/goods_receipt_line.dart';
import '../models/goods_receipt_status.dart';
import '../services/goods_receipt_service.dart';

final goodsReceiptDetailProvider = FutureProvider.autoDispose
    .family<GoodsReceipt, String>((ref, id) async {
      final res = await ref.watch(goodsReceiptServiceProvider).get(id);
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });

class GoodsReceiptDetailScreen extends ConsumerStatefulWidget {
  const GoodsReceiptDetailScreen({super.key, required this.grId});
  final String grId;
  @override
  ConsumerState<GoodsReceiptDetailScreen> createState() =>
      _GoodsReceiptDetailScreenState();
}

class _GoodsReceiptDetailScreenState
    extends ConsumerState<GoodsReceiptDetailScreen> {
  bool _operating = false;

  Future<void> _act(Future<Result<GoodsReceipt>> Function() call) async {
    setState(() => _operating = true);
    final res = await call();
    if (!mounted) return;
    setState(() => _operating = false);
    switch (res) {
      case Success():
        ref.invalidate(goodsReceiptDetailProvider(widget.grId));
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
    final asyncVal = ref.watch(goodsReceiptDetailProvider(widget.grId));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final service = ref.watch(goodsReceiptServiceProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: asyncVal.when(
        loading: () => const Center(child: LoadingSpinner(size: 36)),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () =>
              ref.invalidate(goodsReceiptDetailProvider(widget.grId)),
        ),
        data: (gr) => Column(
          children: [
            _actionBar(gr, service, colors),
            Expanded(
              child: Scrollbar(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _summaryCard(gr, colors),
                    const SizedBox(height: 16),
                    _linesCard(gr, colors, fmt),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBar(
    GoodsReceipt gr,
    GoodsReceiptService service,
    ApexColors colors,
  ) {
    final title = gr.receiptNumber.isNotEmpty
        ? gr.receiptNumber
        : 'Goods Receipt';
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
                      label: gr.status.value,
                      tone: _tone(gr.status),
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
                    if (gr.status == GoodsReceiptStatus.draft)
                      FilledButton.icon(
                        onPressed: _operating
                            ? null
                            : () => _act(() => service.confirm(gr.id)),
                        icon: const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Confirm'),
                      ),
                    if (gr.status.isCancellable)
                      OutlinedButton.icon(
                        onPressed: _operating
                            ? null
                            : () => _act(() => service.cancel(gr.id)),
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
                        label: gr.status.value,
                        tone: _tone(gr.status),
                      ),
                    ],
                  ),
                ),
                if (_operating)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: LoadingSpinner(size: 18),
                  ),
                if (gr.status == GoodsReceiptStatus.draft)
                  FilledButton.icon(
                    onPressed: _operating
                        ? null
                        : () => _act(() => service.confirm(gr.id)),
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
                    label: const Text('Confirm & Post Stock'),
                  ),
                if (gr.status.isCancellable) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _operating
                        ? null
                        : () => _act(() => service.cancel(gr.id)),
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

  Widget _summaryCard(GoodsReceipt gr, ApexColors colors) {
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
                  gr.contactName ?? '—',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Against PO: ${gr.poNumber.isEmpty ? '—' : gr.poNumber}',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
                if ((gr.notes ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      gr.notes!,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _metaRow('Received', gr.receiptDate, colors),
              const SizedBox(height: 10),
              Text('TOTAL RECEIVED', style: _label(colors)),
              Text(
                '${gr.totalReceived}',
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

  Widget _linesCard(GoodsReceipt gr, ApexColors colors, NumberFormatter fmt) {
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
              Expanded(flex: 42, child: Text('ITEM', style: _th(colors))),
              Expanded(
                flex: 20,
                child: Text('WAREHOUSE', style: _th(colors)),
              ),
              Expanded(
                flex: 19,
                child: Text(
                  'ORDERED',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 19,
                child: Text(
                  'RECEIVED',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
            ],
          ),
        ),
        ...gr.lines.asMap().entries.map(
          (e) => _lineRow(e.value, e.key == gr.lines.length - 1, colors, fmt),
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
    GoodsReceiptLine l,
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
        children: [
          Expanded(
            flex: 42,
            child: Text(
              l.productName ?? 'Item',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 20,
            child: Text(
              l.warehouseName ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
            ),
          ),
          Expanded(
            flex: 19,
            child: Text(
              fmt.quantity(l.quantityOrdered),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
          Expanded(
            flex: 19,
            child: Text(
              fmt.quantity(l.quantityReceived),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: l.isComplete ? colors.success : colors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  StatusTone _tone(GoodsReceiptStatus s) => switch (s) {
    GoodsReceiptStatus.draft => StatusTone.neutral,
    GoodsReceiptStatus.confirmed => StatusTone.success,
    GoodsReceiptStatus.cancelled => StatusTone.danger,
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
    this.padding = const EdgeInsets.all(18),
  });
  final ApexColors colors;
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: colors.surfaceRaised,
      borderRadius: BorderRadius.circular(ApexRadius.lg),
      border: Border.all(color: colors.border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );
}
