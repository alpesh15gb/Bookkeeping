import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/product_provider.dart';
import 'package:flutter_client/models/product.dart';
import 'package:flutter_client/views/products/product_form_view.dart';
import 'package:flutter_client/views/shared/app_components.dart';
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

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Search + Filter Bar
          Container(
            color: AppColors.bgSurface,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: 10,
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by name, HSN/SAC or SKU...',
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
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
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['ALL', 'GOODS', 'SERVICE'].map((t) {
                      final isSelected = _typeFilter == t;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(
                            t == 'ALL' ? 'All' : t,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _typeFilter = t),
                          selectedColor: AppColors.brandNavy,
                          backgroundColor: AppColors.borderLight,
                          side: BorderSide.none,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

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
                            padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
                            itemCount: filtered.length,
                            separatorBuilder: (context, _) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final product = filtered[i];
                              return AppCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(product.name, style: AppTextStyles.h3),
                                        ),
                                        StatusBadge.fromProductType(product.productType),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Icon(Icons.monetization_on_outlined, size: 14, color: AppColors.textMuted),
                                        const SizedBox(width: 6),
                                        Text('₹${product.salesPrice.toStringAsFixed(2)}', style: AppTextStyles.bodySmall),
                                        const SizedBox(width: 16),
                                        Icon(Icons.percent_outlined, size: 14, color: AppColors.textMuted),
                                        const SizedBox(width: 6),
                                        Text('${product.gstRate}%', style: AppTextStyles.bodySmall),
                                        const SizedBox(width: 16),
                                        Icon(Icons.inventory_2_outlined, size: 14, color: AppColors.textMuted),
                                        const SizedBox(width: 6),
                                        Text('${product.currentStock} ${product.uom}', style: AppTextStyles.bodySmall),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: () => _showForm(product: product),
                                          icon: const Icon(Icons.edit_outlined, size: 14),
                                          label: const Text('Edit'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            textStyle: AppTextStyles.buttonSmall,
                                            side: const BorderSide(color: AppColors.borderInput),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          onPressed: () async {
                                            final confirm = await AppConfirmDialog.show(
                                              context,
                                              title: 'Delete Product?',
                                              message: 'Are you sure you want to delete ${product.name}?',
                                            );
                                            if (confirm == true) {
                                              final success = await provider.deleteProduct(product.id);
                                              if (!success && mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(provider.errorMessage ?? 'Delete failed'),
                                                    backgroundColor: AppColors.error,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          icon: const Icon(Icons.delete_outlined, size: 14),
                                          label: const Text('Delete'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppColors.error,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            textStyle: AppTextStyles.buttonSmall,
                                            side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                                          ),
                                        ),
                                      ],
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
