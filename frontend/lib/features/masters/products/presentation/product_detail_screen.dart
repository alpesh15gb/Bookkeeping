/// Product detail screen — uses EntityDetailPage.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/entity_detail_page.dart';
import 'package:apexbooks/core/services/favorites_service.dart';
import 'package:apexbooks/core/services/recent_items_service.dart';
import '../data/models/product.dart';
import 'product_controller.dart';
import 'product_form_screen.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = apexColors(context);
    final fmt = ref.read(numberFormatterProvider);

    ref
        .read(recentItemsProvider.notifier)
        .add(
          RecentItem(
            id: product.id,
            title: product.name,
            category: 'products',
            route: '/masters/products/',
          ),
        );

    final favBtn = Consumer(
      builder: (context, ref, _) {
        final favs = ref.watch(favoritesProvider);
        final isFav = favs.any(
          (f) => f.id == product.id && f.category == 'products',
        );
        return IconButton(
          icon: Icon(isFav ? Icons.star_rounded : Icons.star_outline_rounded),
          onPressed: () => ref
              .read(favoritesProvider.notifier)
              .toggle(
                FavoriteItem(
                  id: product.id,
                  title: product.name,
                  category: 'products',
                  route: '/masters/products/',
                ),
              ),
        );
      },
    );

    final header = Row(
      children: [
        CircleAvatar(child: Icon(product.productType.icon)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                product.productType.displayLabel,
                style: TextStyle(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );

    return EntityDetailPage(
      title: product.name,
      header: header,
      appBarActions: [favBtn],
      chips: [
        DetailChip(
          label: product.isActive ? 'Active' : 'Inactive',
          color: product.isActive ? colors.success : colors.danger,
        ),
        DetailChip(label: product.productType.displayLabel, color: colors.info),
        if (product.needsReorder)
          DetailChip(label: 'Low Stock', color: colors.warning),
      ],
      sections: [
        DetailSection(
          title: 'Product Details',
          rows: [
            DetailRow('SKU', product.sku),
            DetailRow('Barcode', product.barcode),
            DetailRow('HSN/SAC', product.hsnSac),
            DetailRow('Unit of Measure', product.uom),
            DetailRow(
              'GST Rate',
              fmt.percent(product.gstRate, showSign: false),
            ),
          ],
        ),
        DetailSection(
          title: 'Pricing',
          rows: [
            DetailRow('Sales Price', fmt.currency(product.salesPrice)),
            DetailRow('Purchase Price', fmt.currency(product.purchasePrice)),
            DetailRow('Margin', '${product.marginPercent.toStringAsFixed(1)}%'),
          ],
        ),
        if (product.productType == ProductType.goods)
          DetailSection(
            title: 'Inventory',
            rows: [
              DetailRow('Opening Stock', fmt.quantity(product.openingStock)),
              DetailRow('Current Stock', fmt.quantity(product.currentStock)),
              DetailRow('Reorder Level', fmt.quantity(product.reorderLevel)),
            ],
          ),
      ],
      actions: [
        ActionItem(
          label: 'Edit',
          icon: Icons.edit_rounded,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProductFormScreen(product: product),
              ),
            );
          },
        ),
        ActionItem(
          label: 'Delete',
          icon: Icons.delete_rounded,
          destructive: true,
          onTap: () async {
            final ok = await ref
                .read(productControllerProvider.notifier)
                .delete(product, context);
            if (ok && context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
      timeline: [
        if (product.createdAt != null)
          TimelineEntry(
            title: 'Created',
            subtitle: 'Product was created',
            timestamp: product.createdAt!,
            icon: Icons.add_circle_outline,
            color: colors.success,
          ),
        if (product.updatedAt != null)
          TimelineEntry(
            title: 'Updated',
            subtitle: 'Product was last modified',
            timestamp: product.updatedAt!,
            icon: Icons.edit_outlined,
            color: colors.info,
          ),
      ],
    );
  }
}
