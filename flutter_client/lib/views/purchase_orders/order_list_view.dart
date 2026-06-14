import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/shared/document_list_view.dart';
import 'package:flutter_client/views/shared/toast.dart';
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

  final _statusOptions = ['ALL', 'DRAFT', 'CONFIRMED', 'DELIVERED', 'RECEIVED', 'CANCELLED'];

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
    final direct = order['contact_name'] ?? order['customer_name'] ?? order['vendor_name'];
    if (direct != null && direct.toString().isNotEmpty) return direct.toString();
    final nested = order['contact'] ?? order['vendor'];
    if (nested is Map && nested['name'] != null) return nested['name'].toString();
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
        fullOrder = await context.read<DocumentProvider>().fetchPurchaseOrderDetail(order['id']);
      } else {
        fullOrder = await context.read<DocumentProvider>().fetchSalesOrderDetail(order['id']);
      }
      if (mounted) Navigator.pop(context);
      if (fullOrder == null) {
        if (mounted) AppToast.error(context, 'Failed to load order details');
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
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel?', message: 'Cancel this order?');
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

  final _transitionLabels = {
    'confirm': 'Confirm',
    'receive': 'Receive',
    'deliver': 'Deliver',
  };

  Future<void> _transition(String id, String type, String action) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: '${_transitionLabels[action]}?',
      message: '${_transitionLabels[action]} this ${type == 'PO' ? 'purchase order' : 'sales order'}?',
      tier: action == 'confirm' ? ActionTier.warning : ActionTier.safe,
      confirmLabel: _transitionLabels[action]!,
    );
    if (confirm != true) return;

    final provider = context.read<DocumentProvider>();
    bool success = false;
    if (type == 'PO') {
      switch (action) {
        case 'confirm': success = await provider.confirmPurchaseOrder(id); break;
        case 'receive': success = await provider.receivePurchaseOrder(id); break;
      }
    } else {
      switch (action) {
        case 'confirm': success = await provider.confirmSalesOrder(id); break;
        case 'deliver': success = await provider.deliverSalesOrder(id); break;
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
      if (mounted) AppToast.error(context, 'Failed to load sales order details');
      return;
    }

    final initialData = Map<String, dynamic>.from(detail);
    initialData['reference_number'] = detail['so_number'];
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => InvoiceFormView(initialData: initialData)),
      ).then((_) => _fetch());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPurchase = widget.orderType == 'purchase';
    final docType = isPurchase ? 'PO' : 'SO';

    final filteredOrders = _allOrders.where((order) {
      final numVal = isPurchase ? order['po_number'] : order['so_number'];
      final partyName = _partyNameFor(order).toLowerCase();
      final matchesSearch = _searchCtrl.text.isEmpty ||
          (numVal?.toString().toLowerCase().contains(_searchCtrl.text.toLowerCase()) == true) ||
          partyName.contains(_searchCtrl.text.toLowerCase());
      final status = order['status'] ?? '';
      final matchesStatus = _statusFilter == 'ALL' || status == _statusFilter;
      return matchesSearch && matchesStatus;
    }).toList();

    final totalCount = _allOrders.length;
    final draftCount = _allOrders.where((o) => o['status'] == 'DRAFT').length;
    final confirmedCount = _allOrders.where((o) => o['status'] == 'CONFIRMED').length;
    final deliveredCount = _allOrders.where((o) => o['status'] == 'DELIVERED').length;
    final receivedCount = _allOrders.where((o) => o['status'] == 'RECEIVED').length;
    final cancelledCount = _allOrders.where((o) => o['status'] == 'CANCELLED').length;

    final docItems = filteredOrders.map((order) {
      final numVal = isPurchase ? order['po_number'] : order['so_number'];
      return DocumentItemData(
        id: order['id'].toString(),
        docNumber: numVal?.toString() ?? 'ORDER',
        partyName: _partyNameFor(order),
        date: (order['issue_date'] ?? order['order_date'] ?? order['created_at'] ?? '').toString(),
        amount: double.tryParse((order['total'] ?? 0).toString()) ?? 0,
        status: order['status'] ?? 'DRAFT',
      );
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPOForm(type: docType),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Expanded(
            child: DocumentListView(
              title: isPurchase ? 'Purchase Orders' : 'Sales Orders',
              searchController: _searchCtrl,
              searchHint: 'Search orders...',
              onSearchChanged: (_) => setState(() {}),
              filterTabs: [
                FilterTab('ALL', totalCount),
                FilterTab('DRAFT', draftCount),
                FilterTab('CONFIRMED', confirmedCount),
                FilterTab('DELIVERED', deliveredCount + receivedCount),
                FilterTab('CANCELLED', cancelledCount),
              ],
              activeFilter: _statusFilter,
              onFilterChanged: (tab) => setState(() => _statusFilter = tab),
              items: docItems,
              isLoading: _isLoading && _allOrders.isEmpty,
              onRefresh: () async => _fetch(),
              emptyTitle: 'No ${isPurchase ? 'purchase' : 'sales'} orders found',
              emptySubtitle: _statusFilter != 'ALL' || _searchCtrl.text.isNotEmpty
                  ? 'Try clearing your filters'
                  : 'Create your first order to get started',
              emptyIcon: Icons.shopping_cart_outlined,
              detailBuilder: (ctx, item) => const SizedBox(),
              itemBuilder: (context, item, index) {
                final order = filteredOrders[index];
                final id = item.id;
                final isSelected = _selectedIds.contains(id);
                final numVal = isPurchase ? order['po_number'] : order['so_number'];
                final partyDisplayName = _partyNameFor(order);

                final itemActions = _isSelectionMode
                    ? <Widget>[]
                    : [
                        if (order['status'] == 'DRAFT') ...[
                          _CompactAction(
                            icon: Icons.edit_outlined,
                            tooltip: 'Edit',
                            onTap: () => _showPOForm(order: order, type: docType),
                          ),
                          _CompactAction(
                            icon: Icons.check_circle_outlined,
                            tooltip: 'Confirm',
                            color: AppColors.warning,
                            onTap: () => _transition(order['id'], docType, 'confirm'),
                          ),
                        ],
                        if (order['status'] == 'CONFIRMED' && isPurchase)
                          _CompactAction(
                            icon: Icons.inbox_outlined,
                            tooltip: 'Receive',
                            onTap: () => _transition(order['id'], docType, 'receive'),
                          ),
                        if (order['status'] == 'CONFIRMED' && !isPurchase)
                          _CompactAction(
                            icon: Icons.local_shipping_outlined,
                            tooltip: 'Deliver',
                            onTap: () => _transition(order['id'], docType, 'deliver'),
                          ),
                        if (order['status'] == 'DELIVERED' && !isPurchase)
                          _CompactAction(
                            icon: Icons.swap_horiz_outlined,
                            tooltip: 'Create Invoice',
                            onTap: () => _convertSalesOrderToInvoice(Map<String, dynamic>.from(order)),
                          ),
                        if (order['status'] != 'CANCELLED' && order['status'] != 'RECEIVED' && order['status'] != 'DELIVERED')
                          _CompactAction(
                            icon: Icons.cancel_outlined,
                            tooltip: 'Cancel',
                            color: AppColors.error,
                            onTap: () => _cancelOrder(order['id'], docType),
                          ),
                        Tooltip(
                          message: 'Share / Print',
                          child: GestureDetector(
                            onTap: () {
                              PrintShareHelper.showShareSheet(
                                context,
                                docLabel: isPurchase ? 'Purchase Order' : 'Sales Order',
                                docNumber: numVal?.toString() ?? 'N/A',
                                docType: isPurchase ? 'purchase-orders' : 'sales-orders',
                                docId: order['id'],
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.brandNavy.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(Icons.share_outlined, size: 14, color: AppColors.brandNavy),
                            ),
                          ),
                        ),
                      ];

                return GestureDetector(
                  onLongPress: () {
                    if (!_isSelectionMode) {
                      setState(() {
                        _isSelectionMode = true;
                        _selectedIds.add(id);
                      });
                    }
                  },
                  child: Row(
                    children: [
                      if (_isSelectionMode)
                        GestureDetector(
                          onTap: () => _toggleSelection(id),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14, right: 8),
                            child: Icon(
                              isSelected ? Icons.check_circle : Icons.circle_outlined,
                              size: 20,
                              color: isSelected ? AppColors.brandNavy : AppColors.textMuted,
                            ),
                          ),
                        ),
                      Expanded(
                        child: AppListTile(
                          leadingText: _isSelectionMode ? null : (numVal?.toString() ?? 'ORDER'),
                          title: partyDisplayName.isNotEmpty ? partyDisplayName : (numVal?.toString() ?? 'ORDER'),
                          subtitle: _isSelectionMode ? null : '${AppDate.format(item.date)} · ${order['status']}',
                          trailingWidget: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppAmount(amount: item.amount.toDouble()),
                              const SizedBox(width: 8),
                              StatusBadge(label: order['status'] ?? ''),
                              if (itemActions.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                ...itemActions,
                              ],
                            ],
                          ),
                          isSelected: isSelected,
                          onTap: () {
                            if (_isSelectionMode) _toggleSelection(id);
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_selectedIds.isNotEmpty)
            AppStickyBottomBar(
              children: [
                Text(
                  '${_selectedIds.length} selected',
                  style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    AppButton(label: 'Clear', icon: Icons.close, isSmall: true, onTap: _clearSelection),
                    const SizedBox(width: 6),
                    AppButton(
                      label: 'Cancel',
                      icon: Icons.cancel_outlined,
                      isSmall: true,
                      color: AppColors.error,
                      textColor: AppColors.textWhite,
                      onTap: _bulkDelete,
                    ),
                  ],
                ),
              ],
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
