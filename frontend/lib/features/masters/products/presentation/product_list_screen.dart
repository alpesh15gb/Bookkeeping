import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/tables/table_column.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/detail_inspector.dart';
import '../data/models/product.dart';
import 'product_controller.dart';
import 'product_form_screen.dart';

final productTableControllerProvider =
    ChangeNotifierProvider.autoDispose<ApexTableController>(
      (ref) => ApexTableController(),
    );

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});
  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  late final ApexTableController _tableCtrl;
  Product? _selected;
  @override
  void initState() {
    super.initState();
    _tableCtrl = ref.read(productTableControllerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final fmt = ref.read(numberFormatterProvider);
    final list = BaseListScreen<Product>(
      title: 'Products',
      tableCtrl: _tableCtrl,
      provider: productControllerProvider,
      onCreate: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ProductFormScreen()))
          .then((_) => ref.invalidate(productControllerProvider)),
      onRowTap: (p) => setState(() => _selected = p),
      searchHint: 'Search catalog…',
      columns: [
        ApexColumn<Product>(
          id: 'name',
          label: 'Name',
          value: (p) => p.name,
          sortable: true,
          width: 220,
          cellBuilder: (_, p, _) => Row(
            children: [
              Icon(p.productType.icon, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    if ((p.sku ?? '').isNotEmpty)
                      Text(
                        p.sku!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: colors.textMuted),
                      ),
                    if ((p.barcode ?? '').isNotEmpty)
                      Text(
                        p.barcode!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ApexColumn(
          id: 'hsn',
          label: 'HSN/SAC',
          value: (p) => p.hsnSac.isEmpty ? '—' : p.hsnSac,
          width: 110,
        ),
        ApexColumn(
          id: 'gst',
          label: 'GST',
          value: (p) => '${p.gstRate.toInt()}%',
          alignment: Alignment.centerRight,
          width: 70,
          cellBuilder: (_, p, _) => Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${p.gstRate.toInt()}%',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
        ),
        ApexColumn(
          id: 'stock',
          label: 'Stock',
          value: (p) => fmt.quantity(p.currentStock),
          sortable: true,
          alignment: Alignment.centerRight,
          width: 110,
          cellBuilder: (_, p, _) => Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (p.needsReorder)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: colors.warning,
                    ),
                  ),
                Text(
                  fmt.quantity(p.currentStock),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.needsReorder ? colors.warning : colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        ApexColumn(
          id: 'price',
          label: 'Price',
          value: (p) => fmt.currency(p.salesPrice),
          sortable: true,
          alignment: Alignment.centerRight,
          width: 110,
          cellBuilder: (_, p, _) => Align(
            alignment: Alignment.centerRight,
            child: Text(
              fmt.currency(p.salesPrice),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
    if (_selected == null) return list;
    if (ResponsiveLayout.isMobile(context)) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            setState(() => _selected = null);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(_selected!.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 20),
                tooltip: 'Edit',
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => ProductFormScreen(product: _selected),
                      ),
                    )
                    .then((_) {
                      ref.invalidate(productControllerProvider);
                      setState(() => _selected = null);
                    }),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: colors.danger,
                ),
                tooltip: 'Delete',
                onPressed: () async {
                  if (await ref
                      .read(productControllerProvider.notifier)
                      .delete(_selected!, context)) {
                    ref.invalidate(productControllerProvider);
                    setState(() => _selected = null);
                    Navigator.of(context).maybePop();
                  }
                },
              ),
            ],
          ),
          body: DetailInspector(
            width: double.infinity,
            title: _selected!.name,
            subtitle: 'Type: ${_selected!.productType.displayLabel}',
            onClose: () => setState(() => _selected = null),
            rows: [
              DetailRow('SKU', _selected!.sku),
              DetailRow('Barcode', _selected!.barcode),
              DetailRow('HSN/SAC', _selected!.hsnSac),
              DetailRow('UOM', _selected!.uom),
              DetailRow('Sales Price', fmt.currency(_selected!.salesPrice)),
              DetailRow('GST Rate', fmt.percent(_selected!.gstRate)),
              DetailRow('Stock', fmt.quantity(_selected!.currentStock)),
            ],
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Edit Product'),
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => ProductFormScreen(product: _selected),
                      ),
                    )
                    .then((_) {
                      ref.invalidate(productControllerProvider);
                      setState(() => _selected = null);
                    }),
              ),
              OutlinedButton.icon(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: colors.danger,
                ),
                label: Text('Delete', style: TextStyle(color: colors.danger)),
                onPressed: () async {
                  if (await ref
                      .read(productControllerProvider.notifier)
                      .delete(_selected!, context)) {
                    ref.invalidate(productControllerProvider);
                    setState(() => _selected = null);
                  }
                },
              ),
            ],
          ),
        ),
      );
    }
    return Row(
      children: [
        Expanded(flex: 3, child: list),
        const VerticalDivider(width: 1),
        DetailInspector(
          width: 320,
          title: _selected!.name,
          subtitle: 'Type: ${_selected!.productType.displayLabel}',
          onClose: () => setState(() => _selected = null),
          rows: [
            DetailRow('SKU', _selected!.sku),
            DetailRow('Barcode', _selected!.barcode),
            DetailRow('HSN/SAC', _selected!.hsnSac),
            DetailRow('UOM', _selected!.uom),
            DetailRow('Sales Price', fmt.currency(_selected!.salesPrice)),
            DetailRow('GST Rate', fmt.percent(_selected!.gstRate)),
            DetailRow('Stock', fmt.quantity(_selected!.currentStock)),
          ],
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Edit Product'),
              onPressed: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => ProductFormScreen(product: _selected),
                    ),
                  )
                  .then((_) {
                    ref.invalidate(productControllerProvider);
                    setState(() => _selected = null);
                  }),
            ),
            OutlinedButton.icon(
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: colors.danger,
              ),
              label: Text('Delete', style: TextStyle(color: colors.danger)),
              onPressed: () async {
                if (await ref
                    .read(productControllerProvider.notifier)
                    .delete(_selected!, context)) {
                  ref.invalidate(productControllerProvider);
                  setState(() => _selected = null);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
