import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/product_provider.dart';
import 'package:flutter_client/models/product.dart';
import 'package:flutter_client/views/products/product_form_view.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/document_list_view.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/utils/haptic_helper.dart';

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

  void _deleteProduct(ProductModel product) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Delete ${product.name}?',
      message: 'This action cannot be undone.',
    );
    if (confirm == true) {
      final provider = context.read<ProductProvider>();
      final success = await provider.deleteProduct(product.id);
      if (success) {
        HapticHelper.delete();
        provider.fetchProducts();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();
    final filtered = _filtered(provider.products);

    final totalCount = provider.products.length;
    final goodsCount = provider.products.where((p) => p.productType == 'GOODS').length;
    final serviceCount = provider.products.where((p) => p.productType == 'SERVICE').length;

    return DocumentListView(
      title: 'Inventory & Items',
      detailBuilder: (ctx, item) => const ProductFormView(),
      items: filtered.map((product) {
        return DocumentItemData(
          id: product.id,
          docNumber: product.hsnSac.isNotEmpty ? product.hsnSac : product.sku ?? '--',
          partyName: product.name,
          date: null,
          amount: product.salesPrice,
          status: product.productType,
        );
      }).toList(),
      filterTabs: [
        FilterTab('ALL', totalCount),
        FilterTab('GOODS', goodsCount),
        FilterTab('SERVICE', serviceCount),
      ],
      activeFilter: _typeFilter,
      onFilterChanged: (tab) {
        setState(() => _typeFilter = tab);
      },
      summary: null,
      searchController: _searchCtrl,
      searchHint: 'Search by name, HSN, SKU...',
      onSearchChanged: (_) => setState(() {}),
      onRefresh: () async => provider.fetchProducts(),
      isLoading: provider.isLoading && provider.products.isEmpty,
      emptyTitle: 'No items found',
      emptySubtitle: _typeFilter != 'ALL' || _searchCtrl.text.isNotEmpty
          ? 'Try clearing your filters'
          : 'Add products and services to track prices and stock',
      emptyIcon: Icons.inventory_2_outlined,
      itemBuilder: (context, item, index) {
        final product = filtered[index];
        return _buildProductCard(product);
      },
    );
  }

  Widget _buildProductCard(ProductModel product) {
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
              StatusBadge.fromProductType(product.productType),
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
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _showForm(product: product);
                  if (value == 'delete') _deleteProduct(product);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                icon: Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _buildSubtitle(ProductModel product) {
    final parts = <String>[];
    if (product.hsnSac.isNotEmpty) parts.add('HSN: ${product.hsnSac}');
    if (product.sku != null && product.sku!.isNotEmpty) parts.add('SKU: ${product.sku}');
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
