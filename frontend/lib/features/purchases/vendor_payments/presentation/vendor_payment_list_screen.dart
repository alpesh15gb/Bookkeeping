import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../models/vendor_payment.dart';
import '../services/vendor_payment_service.dart';
import 'vendor_payment_list_provider.dart';
import 'vendor_payment_form_screen.dart';

class VendorPaymentListScreen extends ConsumerStatefulWidget {
  const VendorPaymentListScreen({super.key});
  @override
  ConsumerState<VendorPaymentListScreen> createState() =>
      _VendorPaymentListScreenState();
}

class _VendorPaymentListScreenState
    extends ConsumerState<VendorPaymentListScreen> {
  VendorPayment? _selected;
  bool _operating = false;
  late final ApexTableController _tableCtrl;

  @override
  void initState() {
    super.initState();
    _tableCtrl = ApexTableController();
    _tableCtrl.addListener(_onTableChange);
  }

  @override
  void dispose() {
    _tableCtrl.removeListener(_onTableChange);
    _tableCtrl.dispose();
    super.dispose();
  }

  void _onTableChange() => setState(() {});

  List<VendorPayment> _sorted(List<VendorPayment> items) {
    final sort = _tableCtrl.value.sort;
    final id = sort.columnId;
    if (id == null) return items;
    final sorted = [...items];
    int cmp(VendorPayment a, VendorPayment b) => switch (id) {
      'paymentNumber' => a.paymentNumber.toLowerCase().compareTo(
        b.paymentNumber.toLowerCase(),
      ),
      'contactName' => a.contactName.toLowerCase().compareTo(
        b.contactName.toLowerCase(),
      ),
      'paymentDate' => a.paymentDate.compareTo(b.paymentDate),
      'amount' => a.amount.compareTo(b.amount),
      _ => 0,
    };
    sorted.sort(cmp);
    return sort.direction == SortDirection.descending
        ? sorted.reversed.toList()
        : sorted;
  }

  Future<void> _cancel(VendorPayment p) async {
    setState(() => _operating = true);
    final res = await ref.read(vendorPaymentServiceProvider).cancel(p.id);
    if (!mounted) return;
    setState(() => _operating = false);
    switch (res) {
      case Success():
        ref.invalidate(vendorPaymentListProvider);
        setState(() => _selected = null);
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
    final asyncVals = ref.watch(vendorPaymentListProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    final list = Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Vendor Payments',
            subtitle: 'Record and allocate payments to vendor bills.',
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New Payment'),
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const VendorPaymentFormScreen(),
                      ),
                    )
                    .then((_) => ref.invalidate(vendorPaymentListProvider)),
              ),
            ],
          ),
          Expanded(
            child: asyncVals.when(
              loading: () => Column(
                children: [
                  for (int i = 0; i < 6; i++)
                    const TableRowSkeleton(
                      columns: 6,
                      columnWidths: [160, 200, 110, 90, 120, 110],
                    ),
                ],
              ),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(vendorPaymentListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.payments_outlined,
                    title: 'No vendor payments yet',
                    subtitle:
                        'Record your first payment against a vendor bill.',
                    actionLabel: 'New Payment',
                    onAction: () => Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => const VendorPaymentFormScreen(),
                          ),
                        )
                        .then((_) => ref.invalidate(vendorPaymentListProvider)),
                  );
                }
                return _table(_sorted(items), colors, fmt);
              },
            ),
          ),
        ],
      ),
    );

    if (_selected == null) return list;
    return Row(
      children: [
        Expanded(flex: 3, child: list),
        const VerticalDivider(width: 1),
        SizedBox(width: 400, child: _inspector(_selected!, colors, fmt)),
      ],
    );
  }

  Widget _table(
    List<VendorPayment> items,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 820,
        child: Column(
          children: [
            Container(
              color: colors.surfaceMuted,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _hd('Payment No.', 'paymentNumber', 160),
                  _hd('Vendor', 'contactName', 200),
                  _hd('Date', 'paymentDate', 110),
                  _hd('Mode', null, 90),
                  _hd('Amount', 'amount', 120, right: true),
                  const SizedBox(
                    width: 110,
                    child: Text(
                      'Status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: colors.border),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final p = items[i];
                  final selected = p.id == _selected?.id;
                  return InkWell(
                    onTap: () => setState(() => _selected = p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      color: selected ? colors.primaryContainer : null,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 160,
                            child: Text(
                              p.paymentNumber.isEmpty ? p.id : p.paymentNumber,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: Text(
                              p.contactName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: Text(
                              p.paymentDate,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 90,
                            child: Text(
                              p.paymentMode.value,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(
                              fmt.currency(p.amount),
                              textAlign: TextAlign.right,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(
                                label: p.status.value,
                                tone: p.status.isActive
                                    ? StatusTone.success
                                    : StatusTone.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hd(
    String label,
    String? columnId,
    double width, {
    bool right = false,
  }) {
    final isSorted =
        columnId != null && _tableCtrl.value.sort.columnId == columnId;
    final asc = _tableCtrl.value.sort.direction == SortDirection.ascending;
    final colors = apexColors(context);
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: columnId == null ? null : () => _tableCtrl.toggleSort(columnId),
        child: Row(
          mainAxisAlignment: right
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isSorted ? colors.primary : null,
                ),
              ),
            ),
            if (columnId != null) ...[
              const SizedBox(width: 4),
              Icon(
                isSorted
                    ? (asc
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded)
                    : Icons.unfold_more_rounded,
                size: 14,
                color: isSorted ? colors.primary : colors.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _inspector(VendorPayment p, ApexColors colors, NumberFormatter fmt) {
    return Container(
      color: colors.surfaceMuted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBar(
            backgroundColor: colors.surfaceMuted,
            elevation: 0,
            title: Text(
              p.paymentNumber.isEmpty ? 'Payment' : p.paymentNumber,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _selected = null),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    StatusBadge(
                      label: p.status.value,
                      tone: p.status.isActive
                          ? StatusTone.success
                          : StatusTone.danger,
                    ),
                    const Spacer(),
                    Text(
                      fmt.currency(p.amount),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _kv('Vendor', p.contactName, colors),
                _kv('Date', p.paymentDate, colors),
                _kv('Mode', p.paymentMode.value, colors),
                if ((p.referenceNumber ?? '').isNotEmpty)
                  _kv('Reference', p.referenceNumber!, colors),
                _kv('Unallocated', fmt.currency(p.unallocatedAmount), colors),
                const SizedBox(height: 16),
                Text(
                  'ALLOCATIONS',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                if (p.allocations.isEmpty)
                  Text(
                    'No allocations',
                    style: TextStyle(fontSize: 13, color: colors.textMuted),
                  )
                else
                  ...p.allocations.map(
                    (a) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              a.billNumber.isEmpty ? a.billId : a.billNumber,
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            fmt.currency(a.amount),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                if (p.status.isCancellable)
                  OutlinedButton.icon(
                    onPressed: _operating ? null : () => _cancel(p),
                    icon: Icon(
                      Icons.cancel_outlined,
                      size: 16,
                      color: colors.danger,
                    ),
                    label: Text(
                      'Cancel Payment',
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
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, ApexColors colors) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            k,
            style: TextStyle(fontSize: 12.5, color: colors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            v.isEmpty ? '—' : v,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}
