import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/purchase_return.dart';
import '../models/purchase_return_line.dart';
import '../models/purchase_return_status.dart';
import '../services/purchase_return_service.dart';

final purchaseReturnDetailProvider = FutureProvider.autoDispose
    .family<PurchaseReturn, String>((ref, id) async {
      final res = await ref.watch(purchaseReturnServiceProvider).get(id);
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });

class PurchaseReturnDetailScreen extends ConsumerStatefulWidget {
  const PurchaseReturnDetailScreen({super.key, required this.returnId});
  final String returnId;
  @override
  ConsumerState<PurchaseReturnDetailScreen> createState() =>
      _PurchaseReturnDetailScreenState();
}

class _PurchaseReturnDetailScreenState
    extends ConsumerState<PurchaseReturnDetailScreen> {
  bool _operating = false;

  Future<void> _act(Future<Result<PurchaseReturn>> Function() call) async {
    setState(() => _operating = true);
    final res = await call();
    if (!mounted) return;
    setState(() => _operating = false);
    switch (res) {
      case Success():
        ref.invalidate(purchaseReturnDetailProvider(widget.returnId));
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
    final asyncVal = ref.watch(purchaseReturnDetailProvider(widget.returnId));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final service = ref.watch(purchaseReturnServiceProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: asyncVal.when(
        loading: () => const Center(child: LoadingSpinner(size: 32)),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () =>
              ref.invalidate(purchaseReturnDetailProvider(widget.returnId)),
        ),
        data: (ret) => Column(
          children: [
            _actionBar(ret, service, colors),
            Expanded(
              child: Scrollbar(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _summaryCard(ret, colors, fmt),
                    const SizedBox(height: 16),
                    _linesCard(ret, colors, fmt),
                    const SizedBox(height: 16),
                    _totalsCard(ret, colors, fmt),
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
    PurchaseReturn ret,
    PurchaseReturnService service,
    ApexColors colors,
  ) {
    final title = ret.returnNumber.isNotEmpty
        ? ret.returnNumber
        : 'Purchase Return';
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
                      label: ret.status.value,
                      tone: _tone(ret.status),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_operating) const LoadingSpinner(size: 18),
                    if (ret.status.isCancellable)
                      OutlinedButton.icon(
                        onPressed: _operating
                            ? null
                            : () => _act(() => service.cancel(ret.id)),
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
                        label: ret.status.value,
                        tone: _tone(ret.status),
                      ),
                    ],
                  ),
                ),
                if (_operating)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: LoadingSpinner(size: 18),
                  ),
                if (ret.status.isCancellable) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _operating
                        ? null
                        : () => _act(() => service.cancel(ret.id)),
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
    PurchaseReturn ret,
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
                  ret.contactName ?? '—',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Against bill: ${ret.billNumber.isEmpty ? '—' : ret.billNumber}',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
                if ((ret.notes ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      ret.notes!,
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Returned  ',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                  Text(
                    ret.returnDate.isEmpty ? '—' : ret.returnDate,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('RETURN TOTAL', style: _label(colors)),
              Text(
                fmt.currency(ret.total),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linesCard(
    PurchaseReturn ret,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
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
              Expanded(flex: 44, child: Text('ITEM', style: _th(colors))),
              Expanded(
                flex: 14,
                child: Text(
                  'QTY',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 20,
                child: Text(
                  'RATE',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 22,
                child: Text(
                  'AMOUNT',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
            ],
          ),
        ),
        ...ret.lines.asMap().entries.map(
          (e) => _lineRow(e.value, e.key == ret.lines.length - 1, colors, fmt),
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
    PurchaseReturnLine l,
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
            flex: 44,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.productName ?? 'Item',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                if ((l.reason ?? '').isNotEmpty)
                  Text(
                    'Reason: ${l.reason}',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 14,
            child: Text(
              fmt.quantity(l.quantityReturned),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
          Expanded(
            flex: 20,
            child: Text(
              fmt.currency(l.rate),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
          Expanded(
            flex: 22,
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

  Widget _totalsCard(
    PurchaseReturn ret,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return Row(
      children: [
        const Spacer(),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveLayout.isMobile(context)
                ? double.infinity
                : 320,
          ),
          child: _Panel(
            colors: colors,
            child: Column(
              children: [
                _totRow('Subtotal', fmt.currency(ret.subtotal), colors),
                if (ret.totalTax != 0)
                  _totRow('Tax', fmt.currency(ret.totalTax), colors),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, color: colors.border),
                ),
                _totRow(
                  'Total',
                  fmt.currency(ret.total),
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
            color: emphasize ? colors.warning : colors.textPrimary,
          ),
        ),
      ],
    ),
  );

  StatusTone _tone(PurchaseReturnStatus s) => switch (s) {
    PurchaseReturnStatus.draft => StatusTone.neutral,
    PurchaseReturnStatus.posted => StatusTone.success,
    PurchaseReturnStatus.cancelled => StatusTone.danger,
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
  const _Panel({required this.colors, required this.child, this.padding});
  final ApexColors colors;
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) =>
      ApexCard(padding: padding ?? const EdgeInsets.all(18), child: child);
}
