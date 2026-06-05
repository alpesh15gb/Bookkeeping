import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/purchase_orders/purchase_order_form_view.dart';
import 'package:flutter_client/views/invoices/invoice_form_view.dart';
import 'package:flutter_client/core/print_share_helper.dart';

class OrderListView extends StatefulWidget {
  final String orderType;
  const OrderListView({super.key, required this.orderType});

  @override
  State<OrderListView> createState() => _OrderListViewState();
}

class _OrderListViewState extends State<OrderListView> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'ALL';
  Set<String> _selectedIds = {};
  bool _isSelectionMode = false;
  List<dynamic> _allOrders = [];
  bool _isLoading = true;

  final _statusOptions = [
    'ALL',
    'DRAFT',
    'CONFIRMED',
    'DELIVERED',
    'RECEIVED',
    'CANCELLED',
  ];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(OrderListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderType != widget.orderType) {
      _clearSelection();
      _fetch();
    }
  }

  void _fetch() async {
    setState(() => _isLoading = true);
    final provider = context.read<DocumentProvider>();
    final orders = widget.orderType == 'purchase'
        ? await provider.fetchPurchaseOrders()
        : await provider.fetchSalesOrders();
    if (mounted) {
      setState(() {
        _allOrders = orders;
        _isLoading = false;
      });
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<dynamic> visibleOrders) {
    setState(() {
      if (_selectedIds.length == visibleOrders.length) {
        _selectedIds.clear();
      } else {
        _selectedIds = visibleOrders.map((e) => e['id'].toString()).toSet();
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  String _partyNameFor(dynamic order) {
    if (order is! Map) return '';
    final direct =
        order['contact_name'] ?? order['customer_name'] ?? order['vendor_name'];
    if (direct != null && direct.toString().isNotEmpty)
      return direct.toString();
    final nested = order['contact'] ?? order['vendor'];
    if (nested is Map && nested['name'] != null)
      return nested['name'].toString();
    return '';
  }

  void _bulkDelete() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel ${_selectedIds.length} items?',
      message: 'This will cancel the selected orders.',
    );
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final isPurchase = widget.orderType == 'purchase';
      for (final id in _selectedIds) {
        if (isPurchase) {
          await provider.deletePurchaseOrder(id);
        } else {
          await provider.deleteSalesOrder(id);
        }
      }
      _clearSelection();
      _fetch();
    }
  }

  void _showPOForm({Map<String, dynamic>? order, String type = 'PO'}) async {
    Map<String, dynamic>? fullOrder = order;
    if (order != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      if (type == 'PO') {
        fullOrder = await context
            .read<DocumentProvider>()
            .fetchPurchaseOrderDetail(order['id']);
      } else {
        fullOrder = await context
            .read<DocumentProvider>()
            .fetchSalesOrderDetail(order['id']);
      }
      if (mounted) Navigator.pop(context);
      if (fullOrder == null) {
        if (mounted) {
          AppToast.error(context, 'Failed to load order details');
        }
        return;
      }
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PurchaseOrderFormView(
            editOrder: fullOrder,
            orderType: type == 'PO' ? 'purchase' : 'sales',
          ),
        ),
      ).then((_) => _fetch());
    }
  }

  Future<void> _cancelOrder(String id, String type) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel?',
      message: 'Cancel this order?',
    );
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = type == 'PO'
          ? await provider.cancelPurchaseOrder(id)
          : await provider.cancelSalesOrder(id);
      if (success) {
        _fetch();
      } else if (mounted) {
        AppToast.error(context, provider.errorMessage ?? 'Cancel failed');
      }
    }
  }

  final Map<String, String> _transitionLabels = {
    'confirm': 'Confirm',
    'receive': 'Receive',
    'deliver': 'Deliver',
  };

  Future<void> _transition(String id, String type, String action) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: '${_transitionLabels[action]}?',
      message:
          '${_transitionLabels[action]} this ${type == 'PO' ? 'purchase order' : 'sales order'}?',
      tier: action == 'confirm' ? ActionTier.warning : ActionTier.safe,
      confirmLabel: _transitionLabels[action]!,
    );
    if (confirm != true) return;

    final provider = context.read<DocumentProvider>();
    bool success = false;
    if (type == 'PO') {
      switch (action) {
        case 'confirm':
          success = await provider.confirmPurchaseOrder(id);
          break;
        case 'receive':
          success = await provider.receivePurchaseOrder(id);
          break;
      }
    } else {
      switch (action) {
        case 'confirm':
          success = await provider.confirmSalesOrder(id);
          break;
        case 'deliver':
          success = await provider.deliverSalesOrder(id);
          break;
      }
    }

    if (success) {
      _fetch();
    } else if (mounted) {
      AppToast.error(context, provider.errorMessage ?? 'Action failed');
    }
  }

  Future<void> _convertSalesOrderToInvoice(Map<String, dynamic> order) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Create Invoice?',
      message: 'Create an invoice from this delivered sales order?',
      tier: ActionTier.safe,
      confirmLabel: 'Create Invoice',
    );
    if (confirm != true) return;

    final id = order['id']?.toString();
    if (id == null) return;

    final provider = context.read<DocumentProvider>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final detail = await provider.fetchSalesOrderDetail(id);
    if (mounted) Navigator.pop(context);

    if (detail == null) {
      if (mounted) {
        AppToast.error(context, 'Failed to load sales order details');
      }
      return;
    }

    final initialData = Map<String, dynamic>.from(detail);
    initialData['reference_number'] = detail['so_number'];
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvoiceFormView(initialData: initialData),
        ),
      ).then((_) => _fetch());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final isPurchase = widget.orderType == 'purchase';
    final docType = isPurchase ? 'PO' : 'SO';

    final filteredOrders = _allOrders.where((order) {
      final numVal = isPurchase ? order['po_number'] : order['so_number'];
      final partyName = _partyNameFor(order).toLowerCase();
      final matchesSearch =
          _searchCtrl.text.isEmpty ||
          (numVal?.toString().toLowerCase().contains(
                _searchCtrl.text.toLowerCase(),
              ) ==
              true) ||
          partyName.contains(_searchCtrl.text.toLowerCase());

      final status = order['status'] ?? '';
      final matchesStatus = _statusFilter == 'ALL' || status == _statusFilter;

      return matchesSearch && matchesStatus;
    }).toList();

    final totalCount = _allOrders.length;
    final draftCount = _allOrders.where((o) => o['status'] == 'DRAFT').length;
    final confirmedCount = _allOrders.where((o) => o['status'] == 'CONFIRMED').length;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: isMobile
          ? FloatingActionButton(
              onPressed: () => _showPOForm(type: docType),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          // ── Search + Filter Bar ──
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
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search orders...',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 18,
                          ),
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
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(
                              color: AppColors.borderInput,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(
                              color: AppColors.borderInput,
                            ),
                          ),
                        ),
                        onChanged: (v) {
                          setState(() {});
                        },
                      ),
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showPOForm(type: docType),
                        icon: const Icon(Icons.add, size: 16, color: AppColors.textWhite),
                        label: const Text(
                          'Create Order',
                          style: TextStyle(fontSize: 12, color: AppColors.textWhite),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandNavy,
                          foregroundColor: AppColors.textWhite,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
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
                        isSelected: _statusFilter == 'ALL',
                        onTap: () => setState(() => _statusFilter = 'ALL'),
                      ),
                      const SizedBox(width: 6),
                      FilterChipWithCount(
                        label: 'Draft', count: draftCount,
                        isSelected: _statusFilter == 'DRAFT',
                        onTap: () => setState(() => _statusFilter = 'DRAFT'),
                      ),
                      const SizedBox(width: 6),
                      FilterChipWithCount(
                        label: 'Confirmed', count: confirmedCount,
                        isSelected: _statusFilter == 'CONFIRMED',
                        onTap: () => setState(() => _statusFilter = 'CONFIRMED'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── List Body ──
          Expanded(
            child: _isLoading && _allOrders.isEmpty
                ? Center(
                    child: LoadingState(
                      message:
                          'Loading ${isPurchase ? 'purchase' : 'sales'} orders...',
                    ),
                  )
                : filteredOrders.isEmpty
                ? EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    title:
                        'No ${isPurchase ? 'purchase' : 'sales'} orders found',
                    subtitle:
                        _statusFilter != 'ALL' || _searchCtrl.text.isNotEmpty
                        ? 'Try clearing your filters'
                        : 'Create your first order to get started',
                    actionLabel: 'Create Order',
                    onAction: () => _showPOForm(type: docType),
                  )
                : Stack(
                    children: [
                      RefreshIndicator(
                        onRefresh: () async => _fetch(),
                        child: ListView.separated(
                          padding: EdgeInsets.only(
                            left: isMobile ? 12 : 20,
                            right: isMobile ? 12 : 20,
                            top: 8,
                            bottom: _selectedIds.isNotEmpty
                                ? 80
                                : (isMobile ? 12 : 20),
                          ),
                          itemCount: filteredOrders.length,
                          separatorBuilder: (context, _) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final order = filteredOrders[i];
                            final id = order['id'].toString();
                            final isSelected = _selectedIds.contains(id);
                            final numVal = isPurchase
                                ? order['po_number']
                                : order['so_number'];
                            final partyDisplayName = _partyNameFor(order);
                            final date = order['issue_date'] ??
                                order['order_date'] ??
                                order['created_at'] ??
                                '';

                            return CompactDocumentCard(
                              docNumber: numVal?.toString() ?? 'ORDER',
                              partyName: partyDisplayName.isNotEmpty
                                  ? partyDisplayName
                                  : null,
                              date: date?.toString(),
                              amount:
                                  double.parse((order['total'] ?? 0).toString()),
                              status: order['status'] ?? '',
                              isSelected: isSelected,
                              isSelectionMode: _isSelectionMode,
                              onTap: () {
                                if (_isSelectionMode) {
                                  _toggleSelection(id);
                                }
                              },
                              onLongPress: () {
                                if (!_isSelectionMode) {
                                  setState(() {
                                    _isSelectionMode = true;
                                    _selectedIds.add(id);
                                  });
                                }
                              },
                              actions: _isSelectionMode
                                  ? null
                                  : [
                                      if (order['status'] == 'DRAFT') ...[
                                        _CompactAction(
                                          icon: Icons.edit_outlined,
                                          tooltip: 'Edit',
                                          onTap: () => _showPOForm(
                                            order: order,
                                            type: docType,
                                          ),
                                        ),
                                        _CompactAction(
                                          icon: Icons.check_circle_outlined,
                                          tooltip: 'Confirm',
                                          color: AppColors.warning,
                                          onTap: () => _transition(
                                            order['id'],
                                            docType,
                                            'confirm',
                                          ),
                                        ),
                                      ],
                                      if (order['status'] == 'CONFIRMED' &&
                                          isPurchase)
                                        _CompactAction(
                                          icon: Icons.inbox_outlined,
                                          tooltip: 'Receive',
                                          onTap: () => _transition(
                                            order['id'],
                                            docType,
                                            'receive',
                                          ),
                                        ),
                                      if (order['status'] == 'CONFIRMED' &&
                                          !isPurchase)
                                        _CompactAction(
                                          icon: Icons.local_shipping_outlined,
                                          tooltip: 'Deliver',
                                          onTap: () => _transition(
                                            order['id'],
                                            docType,
                                            'deliver',
                                          ),
                                        ),
                                      if (order['status'] == 'DELIVERED' &&
                                          !isPurchase)
                                        _CompactAction(
                                          icon: Icons.swap_horiz_outlined,
                                          tooltip: 'Create Invoice',
                                          onTap: () =>
                                              _convertSalesOrderToInvoice(
                                            Map<String, dynamic>.from(order),
                                          ),
                                        ),
                                      if (order['status'] != 'CANCELLED' &&
                                          order['status'] != 'RECEIVED' &&
                                          order['status'] != 'DELIVERED')
                                        _CompactAction(
                                          icon: Icons.cancel_outlined,
                                          tooltip: 'Cancel',
                                          color: AppColors.error,
                                          onTap: () => _cancelOrder(
                                            order['id'],
                                            docType,
                                          ),
                                        ),
                                      Tooltip(
                                        message: 'Share / Print',
                                        child: GestureDetector(
                                          onTap: () {
                                            PrintShareHelper.showShareSheet(
                                              context,
                                              docLabel: isPurchase
                                                  ? 'Purchase Order'
                                                  : 'Sales Order',
                                              docNumber:
                                                  numVal?.toString() ?? 'N/A',
                                              docType: isPurchase
                                                  ? 'purchase-orders'
                                                  : 'sales-orders',
                                              docId: order['id'],
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: AppColors.brandNavy
                                                  .withValues(alpha: 0.08),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Icon(
                                              Icons.share_outlined,
                                              size: 14,
                                              color: AppColors.brandNavy,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                            );
                          },
                        ),
                      ),
                      if (_selectedIds.isNotEmpty)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.bgSurface,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, -2),
                                ),
                              ],
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 12 : 20,
                              vertical: 10,
                            ),
                            child: SafeArea(
                              top: false,
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _selectAll(filteredOrders),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _selectedIds.length ==
                                                  filteredOrders.length
                                              ? Icons.check_circle
                                              : Icons.circle_outlined,
                                          size: 20,
                                          color: _selectedIds.length ==
                                                  filteredOrders.length
                                              ? AppColors.brandNavy
                                              : AppColors.textMuted,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'All',
                                          style: AppTextStyles.caption
                                              .copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${_selectedIds.length} selected',
                                    style: AppTextStyles.caption,
                                  ),
                                  const Spacer(),
                                  ActionButton(
                                    label: 'Clear',
                                    icon: Icons.close,
                                    tier: ActionTier.safe,
                                    onPressed: _clearSelection,
                                  ),
                                  const SizedBox(width: 6),
                                  ActionButton(
                                    label: 'Cancel',
                                    icon: Icons.cancel_outlined,
                                    tier: ActionTier.dangerous,
                                    onPressed: _bulkDelete,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
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
