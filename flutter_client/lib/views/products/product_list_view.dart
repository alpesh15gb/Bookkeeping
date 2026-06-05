import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/product_provider.dart';
import 'package:flutter_client/models/product.dart';
import 'package:flutter_client/views/products/product_form_view.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class ProductListView extends StatefulWidget {
  const ProductListView({super.key});

  @override
  State<ProductListView> createState() => _ProductListViewState();
}

class _ProductListViewState extends State<ProductListView> {
  final _searchCtrl = TextEditingController();
  String _typeFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<ProductProvider>().fetchProducts());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ProductModel> _filtered(List<ProductModel> products) {
    final q = _searchCtrl.text.trim().toLowerCase();
    return products.where((p) {
      final matchesSearch = q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          (p.hsnSac.toLowerCase().contains(q)) ||
          (p.sku?.toLowerCase().contains(q) ?? false);
      final matchesType = _typeFilter == 'ALL' || p.productType == _typeFilter;
      return matchesSearch && matchesType;
    }).toList();
  }

  void _showForm({ProductModel? product}) {
    showDialog(
      context: context,
      builder: (context) => ProductFormView(product: product),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);
    final filtered = _filtered(provider.products);

    // Compute stats
    final totalCount = filtered.length;
    final goodsCount = filtered.where((p) => p.productType == 'GOODS').length;
    final serviceCount = filtered.where((p) => p.productType == 'SERVICE').length;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: isMobile
          ? FloatingActionButton(
              onPressed: () => _showForm(),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          // Search + Filter Bar
          Container(
            color: AppColors.bgSurface,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: 8,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search items...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(color: AppColors.borderInput),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(color: AppColors.borderInput),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showForm(),
                        icon: const Icon(Icons.add, size: 16, color: AppColors.textWhite),
                        label: const Text('Add Item', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandNavy,
                          foregroundColor: AppColors.textWhite,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChipWithCount(
                        label: 'All', count: totalCount,
                        isSelected: _typeFilter == 'ALL',
                        onTap: () => setState(() => _typeFilter = 'ALL'),
                      ),
                      const SizedBox(width: 6),
                      FilterChipWithCount(
                        label: 'Goods', count: goodsCount,
                        isSelected: _typeFilter == 'GOODS',
                        onTap: () => setState(() => _typeFilter = 'GOODS'),
                      ),
                      const SizedBox(width: 6),
                      FilterChipWithCount(
                        label: 'Service', count: serviceCount,
                        isSelected: _typeFilter == 'SERVICE',
                        onTap: () => setState(() => _typeFilter = 'SERVICE'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Summary Stats
          if (provider.products.isNotEmpty)
            SummaryStatsBar(stats: [
              SummaryStat(label: 'Total', count: totalCount, color: AppColors.brandNavy),
              SummaryStat(label: 'Goods', count: goodsCount, color: AppColors.typeGoods),
              SummaryStat(label: 'Services', count: serviceCount, color: AppColors.typeService),
            ]),

          // List
          Expanded(
            child: provider.isLoading && provider.products.isEmpty
                ? const LoadingState(message: 'Loading products...')
                : provider.errorMessage != null && provider.products.isEmpty
                    ? ErrorState(message: provider.errorMessage!, onRetry: () => provider.fetchProducts())
                    : filtered.isEmpty
                        ? EmptyState(
                            icon: Icons.inventory_2_outlined,
                            title: _searchCtrl.text.isNotEmpty || _typeFilter != 'ALL'
                                ? 'No products match your search'
                                : 'No products yet',
                            subtitle: _searchCtrl.text.isNotEmpty || _typeFilter != 'ALL'
                                ? 'Try clearing the filters'
                                : 'Add your first product or service',
                            actionLabel: 'Add Product',
                            onAction: () => _showForm(),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.only(
                              left: isMobile ? 12 : 20,
                              right: isMobile ? 12 : 20,
                              top: 8,
                              bottom: isMobile ? 80 : 20,
                            ),
                            itemCount: filtered.length,
                            separatorBuilder: (context, _) => const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final product = filtered[i];
                              return AppCard(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                onTap: () => _showForm(product: product),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Left: name + metadata
                                    Expanded(
                                      flex: 5,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  product.name,
                                                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              StatusBadge.fromProductType(product.productType),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              Text(
                                                product.hsnSac.isNotEmpty ? 'HSN: ${product.hsnSac}' : '',
                                                style: AppTextStyles.caption,
                                              ),
                                              if (product.sku != null && product.sku!.isNotEmpty) ...[
                                                const SizedBox(width: 12),
                                                Text(
                                                  'SKU: ${product.sku}',
                                                  style: AppTextStyles.caption,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Right: price + GST + stock
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            AmountFormat.format(product.salesPrice),
                                            style: AppTextStyles.amountLarge.copyWith(fontSize: 15),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              Text(
                                                '${product.gstRate.toStringAsFixed(0)}% GST',
                                                style: AppTextStyles.caption,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '${product.currentStock} ${product.uom}',
                                                style: AppTextStyles.caption.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: product.currentStock > 0
                                                      ? AppColors.textPrimary
                                                      : AppColors.error,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Actions
                                    _CompactAction(
                                      icon: Icons.edit_outlined,
                                      tooltip: 'Edit',
                                      onTap: () => _showForm(product: product),
                                    ),
                                    const SizedBox(width: 4),
                                    _CompactAction(
                                      icon: Icons.delete_outline,
                                      tooltip: 'Delete',
                                      color: AppColors.error,
                                      onTap: () async {
                                        final confirm = await AppConfirmDialog.show(
                                          context,
                                          title: 'Delete Product?',
                                          message: 'Are you sure you want to delete ${product.name}?',
                                        );
                                        if (confirm == true) {
                                          final success = await provider.deleteProduct(product.id);
                                          if (!success && mounted) {
                                            AppToast.error(context, provider.errorMessage ?? 'Delete failed');
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _CompactAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _CompactAction({
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: (color ?? AppColors.brandNavy).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 14, color: color ?? AppColors.brandNavy),
        ),
      ),
    );
  }
}
