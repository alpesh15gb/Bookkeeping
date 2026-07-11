import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import '../models/goods_receipt.dart';
import 'goods_receipt_list_provider.dart';
import 'goods_receipt_detail_screen.dart';
import 'goods_receipt_form_screen.dart';
import 'goods_receipt_table_body.dart';

class GoodsReceiptListScreen extends ConsumerStatefulWidget {
  const GoodsReceiptListScreen({super.key});
  @override
  ConsumerState<GoodsReceiptListScreen> createState() =>
      _GoodsReceiptListScreenState();
}

class _GoodsReceiptListScreenState
    extends ConsumerState<GoodsReceiptListScreen> {
  GoodsReceiptListItem? _selected;
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

  List<GoodsReceiptListItem> _sorted(List<GoodsReceiptListItem> items) {
    final sort = _tableCtrl.value.sort;
    final id = sort.columnId;
    if (id == null) return items;
    final sorted = [...items];
    int cmp(GoodsReceiptListItem a, GoodsReceiptListItem b) => switch (id) {
      'receiptNumber' => a.receiptNumber.toLowerCase().compareTo(
        b.receiptNumber.toLowerCase(),
      ),
      'poNumber' => a.poNumber.toLowerCase().compareTo(
        b.poNumber.toLowerCase(),
      ),
      'contactName' => a.contactName.toLowerCase().compareTo(
        b.contactName.toLowerCase(),
      ),
      'receiptDate' => a.receiptDate.compareTo(b.receiptDate),
      _ => 0,
    };
    sorted.sort(cmp);
    return sort.direction == SortDirection.descending
        ? sorted.reversed.toList()
        : sorted;
  }

  @override
  Widget build(BuildContext context) {
    final asyncVals = ref.watch(goodsReceiptListProvider);
    final colors = apexColors(context);

    final list = Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Goods Receipts',
            subtitle: 'Record stock received against purchase orders.',
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New GRN'),
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const GoodsReceiptFormScreen(),
                      ),
                    )
                    .then((_) => ref.invalidate(goodsReceiptListProvider)),
              ),
            ],
          ),
          Expanded(
            child: asyncVals.when(
              loading: () => const Center(child: LoadingSpinner(size: 36)),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(goodsReceiptListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_outlined,
                    title: 'No goods receipts yet',
                    subtitle:
                        'Receive stock against a confirmed purchase order.',
                    actionLabel: 'New Goods Receipt',
                    onAction: () => Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => const GoodsReceiptFormScreen(),
                          ),
                        )
                        .then((_) => ref.invalidate(goodsReceiptListProvider)),
                  );
                }
                return GoodsReceiptTableBody(
                  items: _sorted(items),
                  sort: _tableCtrl.value.sort,
                  onSort: (id) => _tableCtrl.toggleSort(id),
                  selectedId: _selected?.id,
                  onSelect: (item) => setState(() => _selected = item),
                  colors: colors,
                );
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
        Container(
          width: 420,
          color: colors.surfaceMuted,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBar(
                title: Text(
                  _selected!.receiptNumber.isNotEmpty
                      ? _selected!.receiptNumber
                      : 'Goods Receipt',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _selected = null),
                ),
              ),
              Expanded(child: GoodsReceiptDetailScreen(grId: _selected!.id)),
            ],
          ),
        ),
      ],
    );
  }
}
