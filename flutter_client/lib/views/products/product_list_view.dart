import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/product_provider.dart';
import 'package:flutter_client/models/product.dart';
import 'package:flutter_client/views/products/product_form_view.dart';
import 'package:flutter_client/views/shared/app_components.dart' show StatusBadge, ErrorState, SummaryStatsBar, SummaryStat, FilterChipWithCount, AppConfirmDialog, AppToast, LoadingState;
import 'package:flutter_client/views/shared/design_system.dart';
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
                      child: AppInput(
                        controller: _searchCtrl,
                        hint: 'Search items...',
                        prefix: const Icon(Icons.search_rounded, size: 18),
                        suffix: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 8),
                      AppButton(
                        label: 'Add Item',
                        icon: Icons.add,
                        isPrimary: true,
                        onTap: () => _showForm(),
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
                        ? AppEmptyState(
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
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Top row: Name + badge + actions
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            product.name,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        StatusBadge.fromProductType(product.productType),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: const Icon(Icons.share_outlined, size: 16, color: AppColors.textMuted),
                                          tooltip: 'Edit',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _showForm(product: product),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // Subtitle: HSN/SKU
                                    Text(
                                      _buildSubtitle(product),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // Bottom row: 3 metrics
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _ProductMetric(
                                            label: 'Sale Price',
                                            value: AmountFormat.format(product.salesPrice),
                                          ),
                                        ),
                                        Expanded(
                                          child: _ProductMetric(
                                            label: 'Purchase Price',
                                            value: AmountFormat.format(product.purchasePrice),
                                          ),
                                        ),
                                        Expanded(
                                          child: _ProductMetric(
                                            label: 'In Stock',
                                            value: '${product.currentStock} ${product.uom}',
                                            valueColor: product.currentStock < 0
                                                ? AppColors.error
                                                : product.currentStock == 0
                                                    ? AppColors.warning
                                                    : AppColors.textPrimary,
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

  String _buildSubtitle(ProductModel product) {
    final parts = <String>[];
    if (product.hsnSac.isNotEmpty) {
      parts.add('HSN: ${product.hsnSac}');
    }
    if (product.sku != null && product.sku!.isNotEmpty) {
      parts.add('SKU: ${product.sku}');
    }
    return parts.join(' | ');
  }
}

class _ProductMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ProductMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
