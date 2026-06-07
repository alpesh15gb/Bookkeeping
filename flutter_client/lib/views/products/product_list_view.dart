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
import 'package:flutter_client/views/shared/skeleton_loading.dart';

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
    final totalCount = provider.products.length;
    final goodsCount = provider.products.where((p) => p.productType == 'GOODS').length;
    final serviceCount = provider.products.where((p) => p.productType == 'SERVICE').length;

    if (isMobile) {
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showForm(),
          child: const Icon(Icons.add),
        ),
        body: Column(
          children: [
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: AppInput(
                controller: _searchCtrl,
                hint: 'Search items...',
                prefix: const Icon(Icons.search_rounded, size: 16),
                suffix: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                onChanged: (_) => setState(() {}),
              ),
            ),
            AppStatusTabBar(
              tabs: const ['ALL', 'GOODS', 'SERVICE'],
              activeTab: _typeFilter,
              onTabChanged: (tab) {
                setState(() => _typeFilter = tab);
              },
              badges: {
                'ALL': totalCount,
                'GOODS': goodsCount,
                'SERVICE': serviceCount,
              },
            ),
            Expanded(
              child: provider.isLoading && provider.products.isEmpty
                  ? ListSkeleton()
                  : provider.errorMessage != null && provider.products.isEmpty
                      ? ErrorState(message: provider.errorMessage!, onRetry: () => provider.fetchProducts())
                      : filtered.isEmpty
                          ? AppEmptyState(
                              icon: Icons.inventory_2_outlined,
                              title: 'No items match your search',
                              subtitle: 'Try clearing the filters or add an item',
                              actionLabel: 'Add Item',
                              onAction: () => _showForm(),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              itemCount: filtered.length,
                              separatorBuilder: (context, _) => const SizedBox(height: 4),
                              itemBuilder: (context, i) {
                                final product = filtered[i];
                                return AppCard(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              product.name,
                                              style: AppTextStyles.bodyMedium.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.brandNavy,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          AppInlineStatus(status: product.productType),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _buildSubtitle(product),
                                        style: AppTextStyles.bodySmall,
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _ProductMetric(
                                              label: 'SALE',
                                              value: AmountFormat.format(product.salesPrice),
                                            ),
                                          ),
                                          Expanded(
                                            child: _ProductMetric(
                                              label: 'PURCHASE',
                                              value: AmountFormat.format(product.purchasePrice),
                                            ),
                                          ),
                                          Expanded(
                                            child: _ProductMetric(
                                              label: 'STOCK',
                                              value: '${product.currentStock} ${product.uom}',
                                              valueColor: product.currentStock < 0
                                                  ? AppColors.error
                                                  : product.currentStock == 0
                                                      ? AppColors.warning
                                                      : AppColors.success,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 16),
                                            onPressed: () => _showForm(product: product),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
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

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: Column(
        children: [
          AppCommandBar(
            title: 'Inventory & Items',
            searchWidget: AppInput(
              controller: _searchCtrl,
              hint: 'Search by item name, HSN, SKU...',
              prefix: const Icon(Icons.search_rounded, size: 16),
              onChanged: (_) => setState(() {}),
            ),
            actions: [
              AppButton(
                label: 'Add Item',
                icon: Icons.add,
                isPrimary: true,
                onTap: () => _showForm(),
              ),
            ],
          ),
          AppStatusTabBar(
            tabs: const ['ALL', 'GOODS', 'SERVICE'],
            activeTab: _typeFilter,
            onTabChanged: (tab) {
              setState(() => _typeFilter = tab);
            },
            badges: {
              'ALL': totalCount,
              'GOODS': goodsCount,
              'SERVICE': serviceCount,
            },
          ),
          Expanded(
            child: provider.isLoading && provider.products.isEmpty
                ? ListSkeleton()
                : provider.errorMessage != null && provider.products.isEmpty
                    ? ErrorState(message: provider.errorMessage!, onRetry: () => provider.fetchProducts())
                    : filtered.isEmpty
                        ? AppEmptyState(
                            icon: Icons.inventory_2_outlined,
                            title: 'No inventory items found',
                            subtitle: 'Add products and services to track prices and stock',
                            actionLabel: 'Add Item',
                            onAction: () => _showForm(),
                          )
                        : Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                decoration: const BoxDecoration(
                                  color: AppColors.bgSurface,
                                  border: Border(bottom: BorderSide(color: AppColors.border)),
                                ),
                                child: const Row(
                                  children: [
                                    Expanded(flex: 4, child: Text('ITEM / PRODUCT', style: AppTextStyles.labelSmall)),
                                    Expanded(flex: 2, child: Text('HSN / SAC', style: AppTextStyles.labelSmall)),
                                    Expanded(flex: 2, child: Text('SKU', style: AppTextStyles.labelSmall)),
                                    Expanded(flex: 2, child: Text('SALE PRICE', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                                    Expanded(flex: 2, child: Text('PURCHASE PRICE', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                                    Expanded(flex: 2, child: Text('STOCK', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                                    Expanded(flex: 2, child: Text('TYPE', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                                    SizedBox(width: 80, child: Text('ACTIONS', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.borderLight),
                                  itemBuilder: (context, index) {
                                    final item = filtered[index];
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 4,
                                            child: Row(
                                              children: [
                                                AppAvatar(name: item.name, size: 28),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    item.name,
                                                    style: AppTextStyles.bodyMedium.copyWith(
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.brandNavy,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              item.hsnSac.isNotEmpty ? item.hsnSac : '--',
                                              style: AppTextStyles.bodySmall,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              item.sku != null && item.sku!.isNotEmpty ? item.sku! : '--',
                                              style: AppTextStyles.bodySmall,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              AmountFormat.format(item.salesPrice),
                                              style: AppTextStyles.amount,
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              AmountFormat.format(item.purchasePrice),
                                              style: AppTextStyles.amount,
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              '${item.currentStock} ${item.uom}',
                                              style: AppTextStyles.amount.copyWith(
                                                color: item.currentStock < 0
                                                    ? AppColors.error
                                                    : item.currentStock == 0
                                                        ? AppColors.warning
                                                        : AppColors.success,
                                              ),
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Center(
                                              child: AppInlineStatus(status: item.productType),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 80,
                                            child: Center(
                                              child: AppRowActions(
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.edit_outlined, size: 16),
                                                    onPressed: () => _showForm(product: item),
                                                    tooltip: 'Edit',
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
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
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
