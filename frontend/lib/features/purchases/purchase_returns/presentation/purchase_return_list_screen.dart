import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../models/purchase_return.dart';
import 'purchase_return_list_provider.dart';
import 'purchase_return_detail_screen.dart';
import 'purchase_return_form_screen.dart';
import 'purchase_return_table_body.dart';

class PurchaseReturnListScreen extends ConsumerStatefulWidget {
  const PurchaseReturnListScreen({super.key});
  @override
  ConsumerState<PurchaseReturnListScreen> createState() =>
      _PurchaseReturnListScreenState();
}

class _PurchaseReturnListScreenState
    extends ConsumerState<PurchaseReturnListScreen> {
  PurchaseReturnListItem? _selected;
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

  List<PurchaseReturnListItem> _sorted(List<PurchaseReturnListItem> items) {
    final sort = _tableCtrl.value.sort;
    final id = sort.columnId;
    if (id == null) return items;
    final sorted = [...items];
    int cmp(PurchaseReturnListItem a, PurchaseReturnListItem b) => switch (id) {
      'returnNumber' => a.returnNumber.toLowerCase().compareTo(
        b.returnNumber.toLowerCase(),
      ),
      'contactName' => a.contactName.toLowerCase().compareTo(
        b.contactName.toLowerCase(),
      ),
      'returnDate' => a.returnDate.compareTo(b.returnDate),
      'total' => a.total.compareTo(b.total),
      _ => 0,
    };
    sorted.sort(cmp);
    return sort.direction == SortDirection.descending
        ? sorted.reversed.toList()
        : sorted;
  }

  @override
  Widget build(BuildContext context) {
    final asyncVals = ref.watch(purchaseReturnListProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    final list = Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Purchase Returns',
            subtitle: 'Return goods to vendors and raise debit notes.',
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New Return'),
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const PurchaseReturnFormScreen(),
                      ),
                    )
                    .then((_) => ref.invalidate(purchaseReturnListProvider)),
              ),
            ],
          ),
          Expanded(
            child: asyncVals.when(
              loading: () => Column(
                children: [
                  for (int i = 0; i < 6; i++)
                    const TableRowSkeleton(
                      columns: 4,
                      columnWidths: [130, 120, 100, 80],
                    ),
                ],
              ),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(purchaseReturnListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.assignment_return_outlined,
                    title: 'No purchase returns yet',
                    subtitle: 'Return goods against a posted vendor bill.',
                    actionLabel: 'New Purchase Return',
                    onAction: () => Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => const PurchaseReturnFormScreen(),
                          ),
                        )
                        .then(
                          (_) => ref.invalidate(purchaseReturnListProvider),
                        ),
                  );
                }
                return PurchaseReturnTableBody(
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
                  _selected!.returnNumber.isNotEmpty
                      ? _selected!.returnNumber
                      : 'Purchase Return',
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
              Expanded(
                child: PurchaseReturnDetailScreen(returnId: _selected!.id),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
