import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/vendor_bill.dart';
import '../services/vendor_bill_service.dart';
import 'bill_detail_screen.dart';
import 'bill_form_screen.dart';
import 'bill_table_body.dart';
import 'bill_scan_screen.dart';

final billsListProvider = FutureProvider.autoDispose<List<VendorBillListItem>>((
  ref,
) async {
  final res = await ref.watch(vendorBillServiceProvider).list();
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

class BillListScreen extends ConsumerStatefulWidget {
  const BillListScreen({super.key});
  @override
  ConsumerState<BillListScreen> createState() => _BillListScreenState();
}

class _BillListScreenState extends ConsumerState<BillListScreen> {
  VendorBillListItem? _selectedItem;
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

  /// Client-side sort: the vendor-bill service returns a flat list with no
  /// server-side sort params, so we order the rows here without touching the
  /// service or its API contract.
  List<VendorBillListItem> _sorted(List<VendorBillListItem> items) {
    final sort = _tableCtrl.value.sort;
    final columnId = sort.columnId;
    if (columnId == null) return items;
    final sorted = [...items];
    int cmp(VendorBillListItem a, VendorBillListItem b) {
      switch (columnId) {
        case 'billNumber':
          return a.billNumber.toLowerCase().compareTo(
            b.billNumber.toLowerCase(),
          );
        case 'contactName':
          return a.contactName.toLowerCase().compareTo(
            b.contactName.toLowerCase(),
          );
        case 'issueDate':
          return a.issueDate.compareTo(b.issueDate);
        case 'total':
          return a.total.compareTo(b.total);
        default:
          return 0;
      }
    }

    sorted.sort(cmp);
    if (sort.direction == SortDirection.descending) {
      return sorted.reversed.toList();
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final asyncVals = ref.watch(billsListProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    final list = Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Purchase Bills',
            subtitle:
                'Track vendor bills, purchase receipts, and accounts payable.',
            actions: [
              IconButton(
                icon: const Icon(Icons.download_rounded, size: 20),
                tooltip: 'Export list',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Export feature coming soon.')),
                  );
                },
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final created = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => const BillScanScreen()),
                  );
                  if (created == true) ref.invalidate(billsListProvider);
                },
                icon: const Icon(Icons.document_scanner_outlined, size: 18),
                label: const Text('Scan Bill'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BillFormScreen()),
                  );
                  ref.invalidate(billsListProvider);
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Bill'),
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
                      columnWidths: [140, 140, 100, 100],
                    ),
                ],
              ),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(billsListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_outlined,
                    title: 'No bills found',
                    subtitle: 'Add new vendor bills to track payables.',
                  );
                }
                return BillTableBody(
                  items: _sorted(items),
                  sort: _tableCtrl.value.sort,
                  onSort: (id) => _tableCtrl.toggleSort(id),
                  selectedId: _selectedItem?.id,
                  onSelect: (item) => setState(() => _selectedItem = item),
                  fmt: fmt,
                  colors: colors,
                );
              },
            ),
          ),
        ],
      ),
    );

    if (_selectedItem == null) {
      return list;
    }

    return Row(
      children: [
        Expanded(flex: 3, child: list),
        const VerticalDivider(width: 1),
        Container(
          width: 380,
          color: colors.surfaceMuted,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBar(
                title: Text(
                  _selectedItem!.billNumber.isNotEmpty
                      ? _selectedItem!.billNumber
                      : 'Vendor Bill',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _selectedItem = null),
                ),
              ),
              Expanded(child: BillDetailScreen(billId: _selectedItem!.id)),
            ],
          ),
        ),
      ],
    );
  }
}
