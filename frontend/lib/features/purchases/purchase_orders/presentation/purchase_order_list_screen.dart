import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_status.dart';
import 'purchase_order_list_provider.dart';
import 'purchase_order_detail_screen.dart';
import 'purchase_order_form_screen.dart';
import 'purchase_order_table_body.dart';

class PurchaseOrderListScreen extends ConsumerStatefulWidget {
  const PurchaseOrderListScreen({super.key});
  @override
  ConsumerState<PurchaseOrderListScreen> createState() =>
      _PurchaseOrderListScreenState();
}

class _PurchaseOrderListScreenState
    extends ConsumerState<PurchaseOrderListScreen> {
  PurchaseOrderListItem? _selected;
  PurchaseOrderStatus? _statusFilter;
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

  List<PurchaseOrderListItem> _sorted(List<PurchaseOrderListItem> items) {
    final sort = _tableCtrl.value.sort;
    final columnId = sort.columnId;
    if (columnId == null) return items;
    final sorted = [...items];
    int cmp(PurchaseOrderListItem a, PurchaseOrderListItem b) {
      switch (columnId) {
        case 'poNumber':
          return a.poNumber.toLowerCase().compareTo(b.poNumber.toLowerCase());
        case 'contactName':
          return a.contactName.toLowerCase().compareTo(
            b.contactName.toLowerCase(),
          );
        case 'orderDate':
          return a.orderDate.compareTo(b.orderDate);
        case 'dueDate':
          return a.dueDate.compareTo(b.dueDate);
        case 'total':
          return a.total.compareTo(b.total);
        default:
          return 0;
      }
    }

    sorted.sort(cmp);
    return sort.direction == SortDirection.descending
        ? sorted.reversed.toList()
        : sorted;
  }

  @override
  Widget build(BuildContext context) {
    final query = PurchaseOrderListQuery(status: _statusFilter);
    final asyncVals = ref.watch(purchaseOrderListProvider(query));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    final list = Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Purchase Orders',
            subtitle: 'Raise and track vendor purchase orders.',
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New PO'),
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const PurchaseOrderFormScreen(),
                      ),
                    )
                    .then((_) => ref.invalidate(purchaseOrderListProvider)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _StatusFilterBar(
                active: _statusFilter,
                onChanged: (s) => setState(() => _statusFilter = s),
              ),
            ),
          ),
          Expanded(
            child: asyncVals.when(
              loading: () => Column(
                children: [
                  for (int i = 0; i < 6; i++)
                    const TableRowSkeleton(
                      columns: 5,
                      columnWidths: [120, 120, 100, 100, 80],
                    ),
                ],
              ),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(purchaseOrderListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  final filtering = _statusFilter != null;
                  return EmptyState(
                    icon: Icons.description_outlined,
                    title: filtering
                        ? 'No matching purchase orders'
                        : 'No purchase orders yet',
                    subtitle: filtering
                        ? 'Try a different status filter.'
                        : 'Raise your first purchase order to a vendor.',
                    actionLabel: filtering ? null : 'New Purchase Order',
                    onAction: filtering
                        ? null
                        : () => Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const PurchaseOrderFormScreen(),
                                ),
                              )
                              .then(
                                (_) =>
                                    ref.invalidate(purchaseOrderListProvider),
                              ),
                  );
                }
                return PurchaseOrderTableBody(
                  items: _sorted(items),
                  sort: _tableCtrl.value.sort,
                  onSort: (id) => _tableCtrl.toggleSort(id),
                  selectedId: _selected?.id,
                  onSelect: (item) => setState(() => _selected = item),
                  fmt: fmt,
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
                  _selected!.poNumber.isNotEmpty
                      ? _selected!.poNumber
                      : 'Purchase Order',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _selected = null),
                ),
              ),
              Expanded(child: PurchaseOrderDetailScreen(poId: _selected!.id)),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.active, required this.onChanged});
  final PurchaseOrderStatus? active;
  final void Function(PurchaseOrderStatus?) onChanged;

  static const _options = [
    ('All', null),
    ('Draft', PurchaseOrderStatus.draft),
    ('Confirmed', PurchaseOrderStatus.confirmed),
    ('Received', PurchaseOrderStatus.received),
    ('Cancelled', PurchaseOrderStatus.cancelled),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(ApexRadius_md),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _options.map((o) {
          final selected = active == o.$2;
          return GestureDetector(
            onTap: () => onChanged(o.$2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? colors.surfaceRaised : Colors.transparent,
                borderRadius: BorderRadius.circular(ApexRadius_sm),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                o.$1,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? colors.primary : colors.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
