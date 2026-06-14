import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../models/contact.dart';
import '../../../models/product.dart';
import '../../../providers/contact_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../providers/invoice_provider.dart';

class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({super.key});

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  ContactModel? _selectedCustomer;
  final List<_InvoiceLine> _lines = [];
  final TextEditingController _searchController = TextEditingController();
  bool _showCustomerSearch = false;
  String _customerQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactProvider>().fetchContacts();
      context.read<ProductProvider>().fetchProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addLine(ProductModel product) {
    setState(() {
      _lines.add(_InvoiceLine(
        product: product,
        quantity: 1,
        rate: product.salesPrice,
        discount: 0,
      ));
      _showCustomerSearch = false;
    });
  }

  void _removeLine(int index) {
    setState(() => _lines.removeAt(index));
  }

  double get _subtotal => _lines.fold(0.0, (sum, l) => sum + l.subtotal);
  double get _totalDiscount => _lines.fold(0.0, (sum, l) => sum + l.discountAmount);
  double get _totalCgst => _lines.fold(0.0, (sum, l) => sum + l.cgst);
  double get _totalSgst => _lines.fold(0.0, (sum, l) => sum + l.sgst);
  double get _totalIgst => _lines.fold(0.0, (sum, l) => sum + l.igst);
  double get _total => _subtotal - _totalDiscount + _totalCgst + _totalSgst + _totalIgst;

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ContactProvider>().contacts;
    final products = context.watch<ProductProvider>().products;
    final customers = contacts.where((c) => c.contactType == 'CUSTOMER' || c.contactType == 'BOTH').toList();

    final filteredCustomers = _customerQuery.isEmpty
        ? customers
        : customers.where((c) => c.name.toLowerCase().contains(_customerQuery.toLowerCase())).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Create Invoice', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(
              label: 'Save Invoice',
              icon: Icons.save,
              onPressed: _selectedCustomer != null && _lines.isNotEmpty ? _saveInvoice : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: 'More',
              style: AppButtonStyle.secondary,
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CUSTOMER', style: AppTypography.labelMedium),
                          const SizedBox(height: AppSpacing.sm),
                          if (_selectedCustomer != null)
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.person, size: 20, color: AppColors.primary),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_selectedCustomer!.name, style: AppTypography.labelLarge),
                                        if (_selectedCustomer!.phone != null)
                                          Text(_selectedCustomer!.phone!, style: AppTypography.bodySmall),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    onPressed: () => setState(() => _selectedCustomer = null),
                                  ),
                                ],
                              ),
                            )
                          else
                            Column(
                              children: [
                                TextField(
                                  controller: _searchController,
                                  onChanged: (val) => setState(() {
                                    _customerQuery = val;
                                    _showCustomerSearch = true;
                                  }),
                                  onTap: () => setState(() => _showCustomerSearch = true),
                                  decoration: InputDecoration(
                                    hintText: 'Search customer by name, phone, or GSTIN...',
                                    prefixIcon: const Icon(Icons.search, size: 20),
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
                                if (_showCustomerSearch && filteredCustomers.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    constraints: const BoxConstraints(maxHeight: 200),
                                    decoration: BoxDecoration(
                                      color: AppColors.white,
                                      borderRadius: BorderRadius.circular(AppRadius.md),
                                      border: Border.all(color: AppColors.gray200),
                                      boxShadow: AppShadow.elevated,
                                    ),
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      itemCount: filteredCustomers.length.clamp(0, 8),
                                      itemBuilder: (context, index) {
                                        final c = filteredCustomers[index];
                                        return ListTile(
                                          dense: true,
                                          title: Text(c.name, style: AppTypography.bodyMedium),
                                          subtitle: Text(c.phone ?? '', style: AppTypography.bodySmall),
                                          onTap: () {
                                            setState(() {
                                              _selectedCustomer = c;
                                              _showCustomerSearch = false;
                                              _customerQuery = '';
                                            });
                                            _searchController.clear();
                                          },
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sectionGap),

                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('LINE ITEMS', style: AppTypography.labelMedium),
                              const Spacer(),
                              AppButton(
                                label: '+ Add Product',
                                style: AppButtonStyle.ghost,
                                isCompact: true,
                                onPressed: () => _showProductSearch(context, products),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          if (_lines.isEmpty)
                            AppEmptyState(
                              icon: Icons.shopping_cart_outlined,
                              title: 'No products added',
                              subtitle: 'Click "+ Add Product" to add line items',
                            )
                          else
                            ..._lines.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final line = entry.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(line.product.name, style: AppTypography.labelLarge),
                                          Text(
                                            'HSN: ${line.product.hsnSac} • GST: ${line.product.gstRate.toStringAsFixed(0)}%',
                                            style: AppTypography.bodySmall.copyWith(color: AppColors.gray500),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 70,
                                      child: TextField(
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          hintText: 'Qty',
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                                        ),
                                        controller: TextEditingController(text: line.quantity.toStringAsFixed(0)),
                                        onChanged: (val) {
                                          final qty = double.tryParse(val) ?? 1;
                                          setState(() => line.quantity = qty);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    SizedBox(
                                      width: 90,
                                      child: TextField(
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          hintText: 'Rate',
                                          prefixText: '₹ ',
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                                        ),
                                        controller: TextEditingController(text: line.rate.toStringAsFixed(2)),
                                        onChanged: (val) {
                                          final rate = double.tryParse(val) ?? 0;
                                          setState(() => line.rate = rate);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    SizedBox(
                                      width: 60,
                                      child: TextField(
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          hintText: 'Disc',
                                          suffixText: '%',
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                                        ),
                                        controller: TextEditingController(text: line.discount.toStringAsFixed(0)),
                                        onChanged: (val) {
                                          final disc = double.tryParse(val) ?? 0;
                                          setState(() => line.discount = disc);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: AppAmountText(amount: line.lineTotal, style: AppTypography.amountTiny),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.close, size: 16, color: AppColors.gray400),
                                      onPressed: () => _removeLine(idx),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sectionGap),

              SizedBox(
                width: 280,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('INVOICE TOTAL', style: AppTypography.labelMedium),
                      const SizedBox(height: AppSpacing.lg),
                      _buildSummaryRow('Subtotal', _subtotal),
                      const SizedBox(height: AppSpacing.sm),
                      _buildSummaryRow('Discount', -_totalDiscount),
                      if (_totalCgst > 0) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _buildSummaryRow('CGST', _totalCgst),
                      ],
                      if (_totalSgst > 0) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _buildSummaryRow('SGST', _totalSgst),
                      ],
                      if (_totalIgst > 0) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _buildSummaryRow('IGST', _totalIgst),
                      ],
                      const Divider(height: AppSpacing.xl),
                      _buildSummaryRow('TOTAL', _total, isBold: true),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showProductSearch(BuildContext context, List<ProductModel> products) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (context) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = query.isEmpty
                ? products
                : products.where((p) => p.name.toLowerCase().contains(query.toLowerCase())).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.8,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.gray300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: TextField(
                        autofocus: true,
                        onChanged: (val) => setModalState(() => query = val),
                        decoration: InputDecoration(
                          hintText: 'Search products...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: BorderSide(color: AppColors.gray200),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final p = filtered[index];
                          return ListTile(
                            title: Text(p.name, style: AppTypography.bodyMedium),
                            subtitle: Text(
                              '₹${p.salesPrice.toStringAsFixed(2)} • GST ${p.gstRate.toStringAsFixed(0)}% • Stock: ${p.currentStock.toStringAsFixed(0)}',
                              style: AppTypography.bodySmall,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _addLine(p);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _saveInvoice() async {
    if (_selectedCustomer == null || _lines.isEmpty) return;

    final payload = {
      'contact_id': _selectedCustomer!.id,
      'lines': _lines.map((l) => ({
        'product_id': l.product.id,
        'quantity': l.quantity,
        'rate': l.rate,
        'discount': l.discount,
        'hsn_sac': l.product.hsnSac,
        'gst_rate': l.product.gstRate,
      })).toList(),
    };

    final success = await context.read<InvoiceProvider>().createInvoice(payload);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice created successfully')),
      );
      Navigator.of(context).pop();
    }
  }

  Widget _buildSummaryRow(String label, double amount, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: isBold ? AppTypography.labelLarge : AppTypography.bodySmall),
        AppAmountText(
          amount: amount,
          style: isBold ? AppTypography.amountSmall : AppTypography.amountTiny,
        ),
      ],
    );
  }
}

class _InvoiceLine {
  final ProductModel product;
  double quantity;
  double rate;
  double discount;

  _InvoiceLine({
    required this.product,
    required this.quantity,
    required this.rate,
    required this.discount,
  });

  double get subtotal => quantity * rate;
  double get discountAmount => subtotal * (discount / 100);
  double get afterDiscount => subtotal - discountAmount;
  double get cgst => afterDiscount * (product.gstRate / 200);
  double get sgst => afterDiscount * (product.gstRate / 200);
  double get igst => 0.0;
  double get lineTotal => afterDiscount + cgst + sgst + igst;
}
