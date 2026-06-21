import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../models/product.dart';
import '../../../providers/product_provider.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  String? _selectedType;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().fetchProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final products = productProvider.products;
    final isLoading = productProvider.isLoading;

    final filtered = _filterProducts(products);

    final allCount = products.length;
    final goodsCount = products.where((p) => p.productType == 'GOODS').length;
    final servicesCount = products.where((p) => p.productType == 'SERVICE').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Products', style: AppTypography.headlineLarge),
            const Spacer(),
            SizedBox(
              width: 300,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: AppColors.gray200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: AppColors.gray200),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            AppButton(label: '+ Product', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AppFilterChip(label: 'All', count: allCount, isSelected: _selectedType == null, onTap: () => setState(() => _selectedType = null)),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Goods', count: goodsCount, isSelected: _selectedType == 'GOODS', onTap: () => setState(() => _selectedType = 'GOODS')),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Services', count: servicesCount, isSelected: _selectedType == 'SERVICE', onTap: () => setState(() => _selectedType = 'SERVICE')),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && products.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? AppEmptyState(icon: Icons.inventory_2, title: 'No products found')
                  : AppTable(
                      columns: [
                        TableColumn(label: 'Product', width: 220),
                        TableColumn(label: 'SKU', width: 120),
                        TableColumn(label: 'HSN/SAC', width: 100),
                        TableColumn(label: 'Price', width: 120),
                        TableColumn(label: 'Stock', width: 100),
                        TableColumn(label: 'GST', width: 80),
                      ],
                      rows: filtered.map((p) {
                        return AppTableRow(
                          cells: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name, style: AppTypography.bodyMedium),
                                Text(p.productType, style: AppTypography.bodySmall.copyWith(color: AppColors.gray500)),
                              ],
                            ),
                            Text(p.sku ?? '-', style: AppTypography.bodySmall),
                            Text(p.hsnSac, style: AppTypography.bodySmall),
                            AppAmountText(amount: p.salesPrice, style: AppTypography.amountTiny),
                            Text(
                              p.productType == 'SERVICE' ? 'N/A' : p.currentStock.toStringAsFixed(0),
                              style: AppTypography.bodySmall,
                            ),
                            Text('${p.gstRate.toStringAsFixed(0)}%', style: AppTypography.bodySmall),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }

  List<ProductModel> _filterProducts(List<ProductModel> products) {
    var result = products;
    if (_selectedType != null) {
      result = result.where((p) => p.productType == _selectedType).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((p) =>
        p.name.toLowerCase().contains(q) ||
        (p.sku?.toLowerCase().contains(q) ?? false) ||
        p.hsnSac.contains(q)
      ).toList();
    }
    return result;
  }
}
