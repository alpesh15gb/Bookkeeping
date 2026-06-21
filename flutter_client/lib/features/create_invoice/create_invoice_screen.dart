import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../models/contact.dart';
import '../../../models/product.dart';
import '../../../models/terms_template.dart';
import '../../../providers/contact_provider.dart';
import '../../../providers/invoice_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../providers/terms_template_provider.dart';

class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({super.key});

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  ContactModel? _selectedCustomer;
  final List<_InvoiceLine> _lines = [];
  String? _quickDenominator = ',';  // For quick search filtering

  // Track which line has focus for keyboard ops
  int _focusedLineIndex = -1;
  
  // Auto-advance state
  bool _autoAdvanceOnProductSelect = true;
  bool _autoSelectFirstProduct = true;
  
  // Last used defaults
  ContactModel? _lastUsedCustomer;
  ProductModel? _lastUsedProduct;
  
  // Quick mode state (reduced UI friction)
  bool _quickMode = false;

  final TextEditingController _customerSearchController = TextEditingController();
  final TextEditingController _itemSearchController = TextEditingController();
  final TextEditingController _termsController = TextEditingController();

  final FocusNode _customerFocusNode = FocusNode();
  final FocusNode _itemSearchFocusNode = FocusNode();

  bool _showCustomerSearch = false;
  bool _showProductSearch = false;
  String _customerQuery = '';
  String _itemQuery = '';

  bool get _hasValidLines => _lines.isNotEmpty && _lines.every((line) => line.quantity > 0 && line.rate >= 0);
  bool get _canSave => _selectedCustomer != null && _hasValidLines;

  double get _subtotal => _lines.fold(0.0, (sum, line) => sum + line.subtotal);
  double get _totalDiscount => _lines.fold(0.0, (sum, line) => sum + line.discountAmount);
  double get _totalCgst => _lines.fold(0.0, (sum, line) => sum + line.cgst);
  double get _totalSgst => _lines.fold(0.0, (sum, line) => sum + line.sgst);
  double get _totalIgst => _lines.fold(0.0, (sum, line) => sum + line.igst);
  double get _total => _subtotal - _totalDiscount + _totalCgst + _totalSgst + _totalIgst;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ContactProvider>().fetchContacts();
      context.read<ProductProvider>().fetchProducts();
      context.read<TermsTemplateProvider>().fetchTemplates();
      _customerFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _customerSearchController.dispose();
    _itemSearchController.dispose();
    _termsController.dispose();
    _customerFocusNode.dispose();
    _itemSearchFocusNode.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ContactProvider>().contacts;
    final products = context.watch<ProductProvider>().products;
    final invoiceProvider = context.watch<InvoiceProvider>();

    final customers = contacts
        .where((contact) => contact.contactType == 'CUSTOMER' || contact.contactType == 'BOTH')
        .toList();
    final filteredCustomers = _filterCustomers(customers);
    final filteredProducts = _filterProducts(products);

      shortcuts: <ShortcutActivator, Intent>{
        // Save - Ctrl+S is safe (browser uses for Save Page, but web app override is expected)
        SingleActivator(LogicalKeyboardKey.keyS, control: true): const _SaveInvoiceIntent(),
        // Navigation - Use Alt-based shortcuts to avoid browser conflicts
        SingleActivator(LogicalKeyboardKey.keyF, alt: true): const _FocusCustomerIntent(),
        SingleActivator(LogicalKeyboardKey.keyI, alt: true): const _FocusItemIntent(),
        SingleActivator(LogicalKeyboardKey.keyT, alt: true): const _FocusTermsIntent(),
        // Line operations
        SingleActivator(LogicalKeyboardKey.enter): const _AddLineFromSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, control: true): const _AddNewLineIntent(),
        SingleActivator(LogicalKeyboardKey.delete, control: true, shift: true): const _RemoveFocusedLineIntent(),
        // Quantity shortcuts - Numeric keypad focused
        SingleActivator(LogicalKeyboardKey.add): const _IncrementQuantityIntent(),
        SingleActivator(LogicalKeyboardKey.subtract): const _DecrementQuantityIntent(),
        // Actions - Use F-keys (traditional accounting software pattern)
        SingleActivator(LogicalKeyboardKey.f2): const _DuplicateLastLineIntent(),
        SingleActivator(LogicalKeyboardKey.f3): const _ToggleQuickModeIntent(),
        // Escape - Close dropdown without action
        SingleActivator(LogicalKeyboardKey.escape): const _CloseDropdownIntent(),
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyS, control: true): _SaveInvoiceIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SaveInvoiceIntent: CallbackAction<_SaveInvoiceIntent>(
            onInvoke: (_) => _canSave && !invoiceProvider.isLoading ? _saveInvoice() : null,
          ),
          _FocusCustomerIntent: CallbackAction<_FocusCustomerIntent>(
            onInvoke: (_) {
              _customerFocusNode.requestFocus();
              setState(() => _showCustomerSearch = true);
              return null;
            },
          ),
          _FocusItemIntent: CallbackAction<_FocusItemIntent>(
            onInvoke: (_) {
              _itemSearchFocusNode.requestFocus();
              setState(() => _showProductSearch = true);
              return null;
            },
          ),
          _FocusTermsIntent: CallbackAction<_FocusTermsIntent>(
            onInvoke: (_) {
              setState(() {});
              return null;
            },
          ),
          _AddLineFromSearchIntent: CallbackAction<_AddLineFromSearchIntent>(
            onInvoke: (_) {
              if (_itemSearchFocusNode.hasFocus && _showProductSearch) {
                final products = context.read<ProductProvider>().products;
                if (products.isNotEmpty) {
                  _addLine(products.first);
                }
              }
              return null;
            },
          ),
          _AddNewLineIntent: CallbackAction<_AddNewLineIntent>(
            onInvoke: (_) {
              _itemSearchFocusNode.requestFocus();
              setState(() => _showProductSearch = true);
              return null;
            },
          ),
          _RemoveFocusedLineIntent: CallbackAction<_RemoveFocusedLineIntent>(
            onInvoke: (_) {
              if (_focusedLineIndex >= 0 && _focusedLineIndex < _lines.length) {
                _removeLine(_focusedLineIndex);
                _focusedLineIndex = _lines.length > _focusedLineIndex ? _focusedLineIndex : _lines.length - 1;
              }
              return null;
            },
          ),
          _IncrementQuantityIntent: CallbackAction<_IncrementQuantityIntent>(
            onInvoke: (_) {
              if (_focusedLineIndex >= 0 && _focusedLineIndex < _lines.length) {
                _lines[_focusedLineIndex].incrementQuantity();
                setState(() {});
              }
              return null;
            },
          ),
          _DecrementQuantityIntent: CallbackAction<_DecrementQuantityIntent>(
            onInvoke: (_) {
              if (_focusedLineIndex >= 0 && _focusedLineIndex < _lines.length) {
                final line = _lines[_focusedLineIndex];
                if (line.quantity > 1) {
                  line.quantity -= 1;
                  line.quantityController.text = _InvoiceLine._formatInput(line.quantity);
                  setState(() {});
                }
              }
              return null;
            },
          ),
          _DuplicateLastLineIntent: CallbackAction<_DuplicateLastLineIntent>(
            onInvoke: (_) {
              if (_lines.isNotEmpty) {
                final lastLine = _lines.last;
                _addLine(lastLine.product, quantity: lastLine.quantity, rate: lastLine.rate);
              }
              return null;
            },
          ),
          _ToggleQuickModeIntent: CallbackAction<_ToggleQuickModeIntent>(
            onInvoke: (_) {
              setState(() => _quickMode = !_quickMode);
              return null;
            },
          ),
          _CloseDropdownIntent: CallbackAction<_CloseDropdownIntent>(
            onInvoke: (_) {
              if (_showCustomerSearch || _showProductSearch) {
                setState(() {
                  _showCustomerSearch = false;
                  _showProductSearch = false;
                });
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 900;
              final canSave = _canSave && !invoiceProvider.isLoading;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCommandHeader(
                    isCompact: isCompact,
                    canSave: canSave,
                    isSaving: invoiceProvider.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: isCompact
                        ? _buildCompactBody(
                            customers: filteredCustomers,
                            products: filteredProducts,
                            canSave: canSave,
                            isSaving: invoiceProvider.isLoading,
                          )
                        : _buildWideBody(
                            maxWidth: constraints.maxWidth,
                            customers: filteredCustomers,
                            products: filteredProducts,
                            canSave: canSave,
                            isSaving: invoiceProvider.isLoading,
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCommandHeader({
    required bool isCompact,
    required bool canSave,
    required bool isSaving,
  }) {
    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Create Invoice', style: AppTypography.headlineLarge),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Save Invoice',
                  icon: Icons.save_outlined,
                  isLoading: isSaving,
                  onPressed: canSave ? _saveInvoice : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                tooltip: 'Print or share',
                onPressed: null,
                icon: const Icon(Icons.print_outlined),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            'Create Invoice',
            style: AppTypography.headlineLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AppButton(
          label: 'Save Invoice',
          icon: Icons.save_outlined,
          isLoading: isSaving,
          onPressed: canSave ? _saveInvoice : null,
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton(
          tooltip: 'Toggle Quick Mode (Ctrl+P)',
          icon: Icon(_quickMode ? Icons.bolt : Icons.bolt_outlined, color: _quickMode ? AppColors.primary : null),
          onPressed: () => setState(() => _quickMode = !_quickMode),
        ),
        if (_quickMode) ...[
          const SizedBox(width: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _shortcutChip('Ctrl+S', 'Save'),
                const SizedBox(width: AppSpacing.xs),
                _shortcutChip('Ctrl+F', 'Customer'),
                const SizedBox(width: AppSpacing.xs),
                _shortcutChip('Ctrl+I', 'Item'),
                const SizedBox(width: AppSpacing.xs),
                _shortcutChip('Enter', 'Add'),
                const SizedBox(width: AppSpacing.xs),
                _shortcutChip('+/-', 'Qty'),
                const SizedBox(width: AppSpacing.xs),
                _shortcutChip('Ctrl+N', 'New'),
                const SizedBox(width: AppSpacing.xs),
                _shortcutChip('Ctrl+D', 'Dup'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _shortcutChip(String shortcut, String action) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border: Border.all(color: AppColors.gray300, width: 1),
          ),
          child: Text(
            shortcut,
            style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.bold, fontSize: 10),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(action, style: AppTypography.labelSmall.copyWith(color: AppColors.gray600, fontSize: 10)),
      ],
    );
  }

  Widget _buildWideBody({
    required double maxWidth,
    required List<ContactModel> customers,
    required List<ProductModel> products,
    required bool canSave,
    required bool isSaving,
  }) {
    final summaryWidth = maxWidth < 1200 ? 268.0 : 304.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPartyCard(customers: customers),
                const SizedBox(height: AppSpacing.sectionGap),
                _buildItemsCard(products: products, isCompact: false),
                const SizedBox(height: AppSpacing.sectionGap),
                _buildSecondaryDetailsCard(),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sectionGap),
        SizedBox(
          width: summaryWidth,
          child: _buildTotalsCard(canSave: canSave, isSaving: isSaving),
        ),
      ],
    );
  }

  Widget _buildCompactBody({
    required List<ContactModel> customers,
    required List<ProductModel> products,
    required bool canSave,
    required bool isSaving,
  }) {
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 112),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPartyCard(customers: customers),
                const SizedBox(height: AppSpacing.sectionGap),
                _buildItemsCard(products: products, isCompact: true),
                const SizedBox(height: AppSpacing.sectionGap),
                _buildSecondaryDetailsCard(),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _buildMobileSaveBar(canSave: canSave, isSaving: isSaving),
        ),
      ],
    );
  }

  Widget _buildPartyCard({required List<ContactModel> customers}) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('1 Party', style: AppTypography.labelMedium)),
              AppButton(
                label: 'Quick Add',
                icon: Icons.person_add_alt_1_outlined,
                style: AppButtonStyle.ghost,
                isCompact: true,
                onPressed: () => _showQuickAddCustomerDialog(initialName: _customerQuery),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_selectedCustomer == null)
            _buildCustomerSearch(customers)
          else
            _buildSelectedCustomer(),
        ],
      ),
    );
  }

  Widget _buildCustomerSearch(List<ContactModel> customers) {
    return Column(
      children: [
        TextField(
          key: const ValueKey('invoice-party-search'),
          controller: _customerSearchController,
          focusNode: _customerFocusNode,
          textInputAction: TextInputAction.next,
          onChanged: (value) {
            setState(() {
              _customerQuery = value;
              _showCustomerSearch = true;
            });
          },
          onTap: () => setState(() => _showCustomerSearch = true),
          onSubmitted: (_) {
            if (customers.isNotEmpty) {
              _selectCustomer(customers.first);
            } else if (_customerQuery.trim().isNotEmpty) {
              _showQuickAddCustomerDialog(initialName: _customerQuery);
            }
          },
          decoration: _inputDecoration(
            hint: 'Search customer, phone, GSTIN',
            icon: Icons.search,
          ),
        ),
        if (_showCustomerSearch && customers.isNotEmpty)
          _buildSearchMenu(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: customers.take(8).length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final customer = customers[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    customer.name,
                    style: AppTypography.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _customerMeta(customer),
                    style: AppTypography.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _selectCustomer(customer),
                );
              },
            ),
          )
        else if (_showCustomerSearch && _customerQuery.trim().isNotEmpty)
          _buildInlineCreateAction(
            label: 'Create "${_customerQuery.trim()}"',
            icon: Icons.person_add_alt_1_outlined,
            onTap: () => _showQuickAddCustomerDialog(initialName: _customerQuery),
          ),
      ],
    );
  }

  Widget _buildSelectedCustomer() {
    final customer = _selectedCustomer!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(Icons.person_outline, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: AppTypography.labelLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _customerMeta(customer),
                  style: AppTypography.bodySmall.copyWith(color: AppColors.gray600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedCustomer = null;
                _showCustomerSearch = true;
              });
              _customerFocusNode.requestFocus();
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsCard({
    required List<ProductModel> products,
    required bool isCompact,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('2 Items', style: AppTypography.labelMedium)),
              AppButton(
                label: 'Quick Add',
                icon: Icons.add_box_outlined,
                style: AppButtonStyle.ghost,
                isCompact: true,
                onPressed: () => _showQuickAddProductDialog(initialName: _itemQuery),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildProductSearch(products),
          const SizedBox(height: AppSpacing.md),
          if (_lines.isEmpty)
            AppEmptyState(
              icon: Icons.shopping_cart_outlined,
              title: 'No items added',
              subtitle: 'Search and press Enter to add the first item',
            )
          else
            isCompact ? _buildCompactLineItems() : _buildWideLineItems(),
        ],
      ),
    );
  }

  Widget _buildProductSearch(List<ProductModel> products) {
    return Column(
      children: [
        TextField(
          key: const ValueKey('invoice-item-search'),
          controller: _itemSearchController,
          focusNode: _itemSearchFocusNode,
          textInputAction: TextInputAction.done,
          onChanged: (value) {
            setState(() {
              _itemQuery = value;
              _showProductSearch = true;
            });
          },
          onTap: () => setState(() => _showProductSearch = true),
          onSubmitted: (_) {
            if (products.isNotEmpty) {
              _addLine(products.first);
            } else if (_itemQuery.trim().isNotEmpty) {
              _showQuickAddProductDialog(initialName: _itemQuery);
            }
          },
          decoration: _inputDecoration(
            hint: 'Search item, SKU, HSN',
            icon: Icons.inventory_2_outlined,
          ),
        ),
        if (_showProductSearch && products.isNotEmpty)
          _buildSearchMenu(
            maxHeight: 240,
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: products.take(10).length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final product = products[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    product.name,
                    style: AppTypography.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${product.sku ?? product.hsnSac} | GST ${product.gstRate.toStringAsFixed(0)}% | Stock ${product.currentStock.toStringAsFixed(0)}',
                    style: AppTypography.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: AppAmountText(
                    amount: product.salesPrice,
                    style: AppTypography.amountTiny,
                  ),
                  onTap: () => _addLine(product),
                );
              },
            ),
          )
        else if (_showProductSearch && _itemQuery.trim().isNotEmpty)
          _buildInlineCreateAction(
            label: 'Create "${_itemQuery.trim()}"',
            icon: Icons.add_box_outlined,
            onTap: () => _showQuickAddProductDialog(initialName: _itemQuery),
          ),
      ],
    );
  }

  Widget _buildWideLineItems() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.gray50,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Expanded(flex: 4, child: Text('Item', style: AppTypography.labelSmall)),
              SizedBox(width: 72, child: Text('Qty', style: AppTypography.labelSmall)),
              SizedBox(width: 88, child: Text('Rate', style: AppTypography.labelSmall)),
              SizedBox(width: 68, child: Text('Disc', style: AppTypography.labelSmall)),
              SizedBox(width: 56, child: Text('GST', style: AppTypography.labelSmall)),
              SizedBox(
                width: 104,
                child: Text('Amount', style: AppTypography.labelSmall, textAlign: TextAlign.end),
              ),
              const SizedBox(width: 36),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        ..._lines.asMap().entries.map((entry) {
          return _buildWideLineItem(entry.key, entry.value);
        }),
      ],
    );
  }

  Widget _buildWideLineItem(int index, _InvoiceLine line) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.gray100)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.name,
                  style: AppTypography.labelLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'HSN ${line.product.hsnSac} | ${line.product.uom}',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.gray500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: 72, child: _numberField(line.quantityController, 'Qty', (value) => line.quantity = value)),
          const SizedBox(width: AppSpacing.xs),
          SizedBox(width: 84, child: _numberField(line.rateController, 'Rate', (value) => line.rate = value)),
          const SizedBox(width: AppSpacing.xs),
          SizedBox(width: 64, child: _numberField(line.discountController, '%', (value) => line.discount = value)),
          const SizedBox(width: AppSpacing.xs),
          SizedBox(
            width: 52,
            child: Text(
              '${line.product.gstRate.toStringAsFixed(0)}%',
              style: AppTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 104,
            child: AppAmountText(
              amount: line.lineTotal,
              style: AppTypography.amountTiny,
            ),
          ),
          SizedBox(
            width: 36,
            child: IconButton(
              tooltip: 'Remove item',
              icon: Icon(Icons.close, size: 16, color: AppColors.gray500),
              onPressed: () => _removeLine(index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactLineItems() {
    return Column(
      children: _lines.asMap().entries.map((entry) {
        final index = entry.key;
        final line = entry.value;

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.gray50,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.gray200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      line.product.name,
                      style: AppTypography.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove item',
                    icon: Icon(Icons.close, size: 16, color: AppColors.gray500),
                    onPressed: () => _removeLine(index),
                  ),
                ],
              ),
              Text(
                'HSN ${line.product.hsnSac} | GST ${line.product.gstRate.toStringAsFixed(0)}%',
                style: AppTypography.bodySmall.copyWith(color: AppColors.gray500),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: _numberField(line.quantityController, 'Qty', (value) => line.quantity = value)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _numberField(line.rateController, 'Rate', (value) => line.rate = value)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _numberField(line.discountController, 'Disc %', (value) => line.discount = value)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Amount', style: AppTypography.bodySmall),
                  AppAmountText(amount: line.lineTotal, style: AppTypography.amountSmall),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSecondaryDetailsCard() {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          title: Text('3 Terms and secondary details', style: AppTypography.labelMedium),
          children: [_buildTermsEditor()],
        ),
      ),
    );
  }

  Widget _buildTermsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Terms and conditions',
                style: AppTypography.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AppButton(
              label: 'Template',
              icon: Icons.description_outlined,
              style: AppButtonStyle.ghost,
              isCompact: true,
              onPressed: _showTermsTemplatePicker,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const ValueKey('invoice-terms-field'),
          controller: _termsController,
          minLines: 3,
          maxLines: 6,
          decoration: _inputDecoration(
            hint: 'Invoice terms, payment instructions, warranty notes',
          ),
        ),
      ],
    );
  }

  Widget _buildTotalsCard({
    required bool canSave,
    required bool isSaving,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Invoice Total',
                  style: AppTypography.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${_lines.length} item${_lines.length == 1 ? '' : 's'}', style: AppTypography.bodySmall),
            ],
          ),
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
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'Save Invoice',
              icon: Icons.save_outlined,
              isLoading: isSaving,
              onPressed: canSave ? _saveInvoice : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileSaveBar({
    required bool canSave,
    required bool isSaving,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.gray200)),
        boxShadow: AppShadow.elevated,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total', style: AppTypography.bodySmall),
                  AppAmountText(amount: _total, style: AppTypography.amountMedium),
                ],
              ),
            ),
            SizedBox(
              width: 164,
              child: AppButton(
                label: 'Save',
                icon: Icons.save_outlined,
                isLoading: isSaving,
                onPressed: canSave ? _saveInvoice : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchMenu({
    required Widget child,
    double maxHeight = 220,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gray200),
        boxShadow: AppShadow.elevated,
      ),
      child: child,
    );
  }

  Widget _buildInlineCreateAction({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gray200),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, size: 18, color: AppColors.primary),
        title: Text(label, style: AppTypography.labelMedium),
        onTap: onTap,
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String hint,
    ValueChanged<double> onValueChanged,
  ) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      onChanged: (value) {
        final parsed = double.tryParse(value);
        if (parsed == null) return;
        setState(() => onValueChanged(parsed));
      },
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: AppColors.gray200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    IconData? icon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: AppColors.gray200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: AppColors.gray200),
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: isBold ? AppTypography.labelLarge : AppTypography.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppAmountText(
          amount: amount,
          style: isBold ? AppTypography.amountSmall : AppTypography.amountTiny,
        ),
      ],
    );
  }

  List<ContactModel> _filterCustomers(List<ContactModel> customers) {
    final query = _customerQuery.trim().toLowerCase();
    if (query.isEmpty) return customers;
    return customers.where((customer) {
      final values = [
        customer.name,
        customer.phone ?? '',
        customer.gstin ?? '',
      ].map((value) => value.toLowerCase());
      return values.any((value) => value.contains(query));
    }).toList();
  }

  List<ProductModel> _filterProducts(List<ProductModel> products) {
    final query = _itemQuery.trim().toLowerCase();
    if (query.isEmpty) return products;
    return products.where((product) {
      final values = [
        product.name,
        product.sku ?? '',
        product.hsnSac,
      ].map((value) => value.toLowerCase());
      return values.any((value) => value.contains(query));
    }).toList();
  }

  String _customerMeta(ContactModel customer) {
    final parts = <String>[
      if ((customer.phone ?? '').isNotEmpty) customer.phone!,
      if ((customer.gstin ?? '').isNotEmpty) 'GSTIN ${customer.gstin}',
      if (customer.stateCode.isNotEmpty) 'State ${customer.stateCode}',
    ];
    return parts.isEmpty ? customer.registrationType : parts.join(' | ');
  }

  void _selectCustomer(ContactModel customer) {
    setState(() {
      _selectedCustomer = customer;
      _lastUsedCustomer = customer;
      _showCustomerSearch = false;
      _customerQuery = '';
    });
    _customerSearchController.clear();
    _itemSearchFocusNode.requestFocus();
  }

  void _addLine(ProductModel product, {double? quantity, double? rate}) {
    setState(() {
      final existingIndex = _lines.indexWhere((line) => line.product.id == product.id);
      if (existingIndex >= 0) {
        _lines[existingIndex].incrementQuantity();
        _focusedLineIndex = existingIndex;
      } else {
        _lines.add(
          _InvoiceLine(
            product: product,
            quantity: quantity ?? 1,
            rate: rate ?? product.salesPrice,
            discount: 0,
          ),
        );
        _focusedLineIndex = _lines.length - 1;
        _lastUsedProduct = product;
      }
      _showProductSearch = false;
      _itemQuery = '';
    });
    _itemSearchController.clear();
    
    // Auto-focus the quantity field of the newly added line
    if (_focusedLineIndex >= 0 && _focusedLineIndex < _lines.length) {
      _lines[_focusedLineIndex].focus();
    }
  }

  void _removeLine(int index) {
    setState(() {
      final line = _lines.removeAt(index);
      line.dispose();
    });
  }

  Future<void> _showQuickAddCustomerDialog({String? initialName}) async {
    final nameController = TextEditingController(text: initialName?.trim() ?? '');
    final phoneController = TextEditingController();
    final gstinController = TextEditingController();

    final contact = await showDialog<ContactModel>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Quick Add Customer'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(hint: 'Customer name'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: phoneController,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration(hint: 'Phone'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: gstinController,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.characters,
                  decoration: _inputDecoration(hint: 'GSTIN'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  ContactModel(
                    id: 'local-${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                    gstin: gstinController.text.trim().isEmpty ? null : gstinController.text.trim().toUpperCase(),
                    contactType: 'CUSTOMER',
                    registrationType: gstinController.text.trim().isEmpty ? 'CONSUMER' : 'REGULAR',
                    billingAddress: const {},
                    stateCode: '27',
                    isActive: true,
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
    gstinController.dispose();

    if (contact == null) return;
    final provider = context.read<ContactProvider>();
    final success = await provider.addContact(contact);
    if (!mounted) return;
    if (success) {
      _selectCustomer(provider.lastCreatedContact ?? contact);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer added')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage ?? 'Failed to add customer')),
      );
    }
  }

  Future<void> _showQuickAddProductDialog({String? initialName}) async {
    final nameController = TextEditingController(text: initialName?.trim() ?? '');
    final rateController = TextEditingController();
    final gstController = TextEditingController(text: '18');
    final hsnController = TextEditingController();

    final product = await showDialog<ProductModel>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Quick Add Item'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(hint: 'Item name'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: rateController,
                  textInputAction: TextInputAction.next,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _inputDecoration(hint: 'Sales rate'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: gstController,
                  textInputAction: TextInputAction.next,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _inputDecoration(hint: 'GST %'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: hsnController,
                  textInputAction: TextInputAction.done,
                  decoration: _inputDecoration(hint: 'HSN/SAC'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  ProductModel(
                    id: 'local-${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    hsnSac: hsnController.text.trim(),
                    productType: 'GOODS',
                    uom: 'PCS',
                    salesPrice: double.tryParse(rateController.text.trim()) ?? 0,
                    purchasePrice: 0,
                    gstRate: double.tryParse(gstController.text.trim()) ?? 0,
                    openingStock: 0,
                    currentStock: 0,
                    reorderLevel: 0,
                    isActive: true,
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    rateController.dispose();
    gstController.dispose();
    hsnController.dispose();

    if (product == null) return;
    final provider = context.read<ProductProvider>();
    final success = await provider.addProduct(product);
    if (!mounted) return;
    if (success) {
      _addLine(provider.lastCreatedProduct ?? product);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item added')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage ?? 'Failed to add item')),
      );
    }
  }

  Future<void> _showTermsTemplatePicker() async {
    final provider = context.read<TermsTemplateProvider>();
    if (provider.items.isEmpty && !provider.isLoading) {
      await provider.fetchTemplates();
    }
    if (!mounted) return;

    final selected = await showDialog<_TermsTemplateSelection>(
      context: context,
      builder: (dialogContext) => _TermsTemplatePickerDialog(
        templates: provider.items,
        hasExistingTerms: _termsController.text.trim().isNotEmpty,
      ),
    );

    if (selected == null) return;
    setState(() {
      if (selected.mode == _TermsApplyMode.append && _termsController.text.trim().isNotEmpty) {
        _termsController.text = '${_termsController.text.trim()}\n\n${selected.template.content}';
      } else {
        _termsController.text = selected.template.content;
      }
    });
  }

  Future<void> _saveInvoice() async {
    if (!_canSave) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a customer and add valid item lines')),
      );
      return;
    }

    final invoiceProvider = context.read<InvoiceProvider>();
    final payload = {
      'contact_id': _selectedCustomer!.id,
      'lines': _lines
          .map(
            (line) => {
              'product_id': line.product.id,
              'quantity': line.quantity,
              'rate': line.rate,
              'discount': line.discount,
              'hsn_sac': line.product.hsnSac,
              'gst_rate': line.product.gstRate,
            },
          )
          .toList(),
      'terms_and_conditions': _termsController.text.trim(),
    };

    final success = await invoiceProvider.createInvoice(payload);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice created successfully')),
      );
      Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(invoiceProvider.errorMessage ?? 'Failed to create invoice')),
      );
    }
  }
}

class _InvoiceLine {
  final ProductModel product;
  final TextEditingController quantityController;
  final TextEditingController rateController;
  final TextEditingController discountController;
  double quantity;
  double rate;
  double discount;

  _InvoiceLine({
    required this.product,
    required this.quantity,
  void focus() {
    quantityController.selection = TextSelection(baseOffset: 0, extentOffset: quantityController.text.length);
  }
    required this.rate,
    required this.discount,
  })  : quantityController = TextEditingController(text: _formatInput(quantity)),
        rateController = TextEditingController(text: _formatInput(rate)),
        discountController = TextEditingController(text: _formatInput(discount));

  double get subtotal => quantity * rate;
  double get discountAmount => subtotal * (discount / 100);
  double get afterDiscount => subtotal - discountAmount;
  double get cgst => afterDiscount * (product.gstRate / 200);
  double get sgst => afterDiscount * (product.gstRate / 200);
  double get igst => 0.0;
  double get lineTotal => afterDiscount + cgst + sgst + igst;

  void incrementQuantity() {
    quantity += 1;
    quantityController.text = _formatInput(quantity);
  }

  void dispose() {
    quantityController.dispose();
    rateController.dispose();
    discountController.dispose();
  }

  static String _formatInput(double value) {
    return value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }
}

class _SaveInvoiceIntent extends Intent {
  const _SaveInvoiceIntent();
}
class _FocusCustomerIntent extends Intent { const _FocusCustomerIntent(); }
class _FocusItemIntent extends Intent { const _FocusItemIntent(); }
class _FocusCustomerIntent extends Intent { const _FocusCustomerIntent(); }
class _FocusItemIntent extends Intent { const _FocusItemIntent(); }
class _FocusTermsIntent extends Intent { const _FocusTermsIntent(); }
class _AddLineFromSearchIntent extends Intent { const _AddLineFromSearchIntent(); }
class _AddNewLineIntent extends Intent { const _AddNewLineIntent(); }
class _RemoveFocusedLineIntent extends Intent { const _RemoveFocusedLineIntent(); }
class _IncrementQuantityIntent extends Intent { const _IncrementQuantityIntent(); }
class _DecrementQuantityIntent extends Intent { const _DecrementQuantityIntent(); }
class _DuplicateLastLineIntent extends Intent { const _DuplicateLastLineIntent(); }
class _ToggleQuickModeIntent extends Intent { const _ToggleQuickModeIntent(); }
class _CloseDropdownIntent extends Intent { const _CloseDropdownIntent(); }
class _FocusTermsIntent extends Intent { const _FocusTermsIntent(); }
class _AddLineFromSearchIntent extends Intent { const _AddLineFromSearchIntent(); }
class _AddNewLineIntent extends Intent { const _AddNewLineIntent(); }
class _RemoveFocusedLineIntent extends Intent { const _RemoveFocusedLineIntent(); }
class _IncrementQuantityIntent extends Intent { const _IncrementQuantityIntent(); }
class _DecrementQuantityIntent extends Intent { const _DecrementQuantityIntent(); }
class _DuplicateLastLineIntent extends Intent { const _DuplicateLastLineIntent(); }
class _ToggleQuickModeIntent extends Intent { const _ToggleQuickModeIntent(); }

enum _TermsApplyMode { replace, append }

class _TermsTemplateSelection {
  final TermsTemplateModel template;
  final _TermsApplyMode mode;

  const _TermsTemplateSelection({
    required this.template,
    required this.mode,
  });
}

class _TermsTemplatePickerDialog extends StatefulWidget {
  final List<TermsTemplateModel> templates;
  final bool hasExistingTerms;

  const _TermsTemplatePickerDialog({
    required this.templates,
    required this.hasExistingTerms,
  });

  @override
  State<_TermsTemplatePickerDialog> createState() => _TermsTemplatePickerDialogState();
}

class _TermsTemplatePickerDialogState extends State<_TermsTemplatePickerDialog> {
  TermsTemplateModel? _selected;
  _TermsApplyMode _mode = _TermsApplyMode.replace;

  @override
  void initState() {
    super.initState();
    _selected = widget.templates.isNotEmpty ? widget.templates.first : null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Apply Terms Template'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: widget.templates.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text('No terms templates found.'),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final stack = constraints.maxWidth < 520;
                  final list = _buildTemplateList();
                  final preview = _buildPreview();

                  if (stack) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: 180, child: list),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(height: 180, child: preview),
                        _buildModeSelector(),
                      ],
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 300,
                        child: Row(
                          children: [
                            SizedBox(width: 220, child: list),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: preview),
                          ],
                        ),
                      ),
                      _buildModeSelector(),
                    ],
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(
                    context,
                    _TermsTemplateSelection(template: _selected!, mode: _mode),
                  ),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _buildTemplateList() {
    return ListView.separated(
      itemCount: widget.templates.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final template = widget.templates[index];
        final selected = template.id == _selected?.id;
        return ListTile(
          dense: true,
          selected: selected,
          title: Text(
            template.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: template.isPreset ? const Text('Preset') : null,
          onTap: () => setState(() => _selected = template),
        );
      },
    );
  }

  Widget _buildPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gray200),
      ),
      child: SingleChildScrollView(
        child: Text(
          _selected?.content ?? '',
          style: AppTypography.bodySmall.copyWith(color: AppColors.gray700),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    if (!widget.hasExistingTerms) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: SegmentedButton<_TermsApplyMode>(
        segments: const [
          ButtonSegment(value: _TermsApplyMode.replace, label: Text('Replace')),
          ButtonSegment(value: _TermsApplyMode.append, label: Text('Append')),
        ],
        selected: {_mode},
        onSelectionChanged: (value) {
          setState(() => _mode = value.first);
        },
      ),
    );
  }
}
