import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/purchase_orders/purchase_order_form_view.dart';
import 'package:flutter_client/core/print_share_helper.dart';

class OrderListView extends StatefulWidget {
  final String orderType; // 'purchase' or 'sales'
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load order details'), backgroundColor: AppColors.error),
          );
        }
        return;
      }
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PurchaseOrderFormView(editOrder: fullOrder, orderType: type == 'PO' ? 'purchase' : 'sales'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Cancel failed'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  final Map<String, String> _transitionLabels = {
    'confirm': 'Confirm', 'receive': 'Receive', 'deliver': 'Deliver', 'convert': 'Convert to Invoice',
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
        case 'confirm': success = await provider.confirmPurchaseOrder(id);
        case 'receive': success = await provider.receivePurchaseOrder(id);
      }
    } else {
      switch (action) {
        case 'confirm': success = await provider.confirmSalesOrder(id);
        case 'deliver': success = await provider.deliverSalesOrder(id);
        case 'convert': success = await provider.convertSalesOrder(id);
      }
    }

    if (success) {
      _fetch();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage ?? 'Action failed'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final isPurchase = widget.orderType == 'purchase';
    final docType = isPurchase ? 'PO' : 'SO';

    final filteredOrders = _allOrders.where((order) {
      final numVal = isPurchase ? order['po_number'] : order['so_number'];
      final partyName = (order['contact'] ?? order['vendor'])?['name']?.toString().toLowerCase() ?? '';
      final matchesSearch = _searchCtrl.text.isEmpty ||
          (numVal?.toString().toLowerCase().contains(_searchCtrl.text.toLowerCase()) == true) ||
          partyName.contains(_searchCtrl.text.toLowerCase());
      
      final status = order['status'] ?? '';
      final matchesStatus = _statusFilter == 'ALL' || status == _statusFilter;
      
      return matchesSearch && matchesStatus;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPOForm(type: docType),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // ── Search + Filter Bar ──
          Container(
            color: AppColors.bgSurface,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: 10,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search by order number or party...',
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
                        onChanged: (v) {
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Status filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _statusOptions.where((s) {
                      if (isPurchase && s == 'DELIVERED') return false;
                      if (!isPurchase && s == 'RECEIVED') return false;
                      return true;
                    }).map((s) {
                      final isSelected = _statusFilter == s;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(
                            s == 'ALL' ? 'All' : s.replaceAll('_', ' '),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _statusFilter = s);
                          },
                          selectedColor: AppColors.brandNavy,
                          backgroundColor: AppColors.borderLight,
                          side: BorderSide.none,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
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

          // ── List Body ──
          Expanded(
            child: _isLoading && _allOrders.isEmpty
                ? Center(child: LoadingState(message: 'Loading ${isPurchase ? 'purchase' : 'sales'} orders...'))
                : filteredOrders.isEmpty
                    ? EmptyState(
                        icon: Icons.shopping_cart_outlined,
                        title: 'No ${isPurchase ? 'purchase' : 'sales'} orders found',
                        subtitle: _statusFilter != 'ALL' || _searchCtrl.text.isNotEmpty
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
                                top: isMobile ? 12 : 20,
                                bottom: _selectedIds.isNotEmpty ? 80 : (isMobile ? 12 : 20),
                              ),
                              itemCount: filteredOrders.length,
                              separatorBuilder: (context, _) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final order = filteredOrders[i];
                                final id = order['id'].toString();
                                final isSelected = _selectedIds.contains(id);
                                final numVal = isPurchase ? order['po_number'] : order['so_number'];
                                return GestureDetector(
                                  onLongPress: () {
                                    if (!_isSelectionMode) {
                                      setState(() {
                                        _isSelectionMode = true;
                                        _selectedIds.add(id);
                                      });
                                    }
                                  },
                                  child: AppCard(
                                    onTap: () {
                                      if (_isSelectionMode) {
                                        _toggleSelection(id);
                                      }
                                    },
                                    child: Row(
                                      children: [
                                        if (_isSelectionMode)
                                          Padding(
                                            padding: const EdgeInsets.only(right: 12),
                                            child: Icon(
                                              isSelected ? Icons.check_circle : Icons.circle_outlined,
                                              size: 22,
                                              color: isSelected ? AppColors.brandNavy : AppColors.textMuted,
                                            ),
                                          ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(child: Text(numVal?.toString() ?? 'ORDER', style: AppTextStyles.h3)),
                                                  if (order['status'] != null) StatusBadge(label: order['status']),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  if (order['contact'] != null || order['vendor'] != null) ...[
                                                    Icon(Icons.person_outlined, size: 14, color: AppColors.textMuted),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      (order['contact'] ?? order['vendor'])?['name']?.toString() ?? 'N/A',
                                                      style: AppTextStyles.bodySmall,
                                                    ),
                                                    const SizedBox(width: 16),
                                                  ],
                                                  Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textMuted),
                                                  const SizedBox(width: 6),
                                                  Text(order['issue_date'] ?? order['order_date'] ?? order['created_at'] ?? '', style: AppTextStyles.caption),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text('₹${double.parse((order['total'] ?? 0).toString()).toStringAsFixed(2)}', style: AppTextStyles.numericLarge),
                                                  if (!_isSelectionMode)
                                                    Row(
                                                      children: [
                                                        IconButton(
                                                          icon: const Icon(Icons.share_outlined, size: 16),
                                                          onPressed: () {
                                                            PrintShareHelper.showShareSheet(
                                                              context,
                                                              docLabel: isPurchase ? 'Purchase Order' : 'Sales Order',
                                                              docNumber: numVal?.toString() ?? 'N/A',
                                                              docType: isPurchase ? 'purchase-orders' : 'sales-orders',
                                                              docId: order['id'],
                                                            );
                                                          },
                                                          tooltip: 'Share / Print',
                                                        ),
                                                        const SizedBox(width: 4),
                                                        if (order['status'] == 'DRAFT') ...[
                                                          OutlinedButton.icon(
                                                            onPressed: () => _showPOForm(order: order, type: docType),
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
                                                            onPressed: () => _transition(order['id'], docType, 'confirm'),
                                                            icon: const Icon(Icons.check_circle_outlined, size: 14),
                                                            label: const Text('Confirm'),
                                                            style: OutlinedButton.styleFrom(
                                                              foregroundColor: AppColors.success,
                                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                              textStyle: AppTextStyles.buttonSmall,
                                                              side: BorderSide(color: AppColors.success.withValues(alpha: 0.3)),
                                                            ),
                                                          ),
                                                        ],
                                                        if (order['status'] == 'CONFIRMED' && isPurchase) ...[
                                                          OutlinedButton.icon(
                                                            onPressed: () => _transition(order['id'], docType, 'receive'),
                                                            icon: const Icon(Icons.inbox_outlined, size: 14),
                                                            label: const Text('Receive'),
                                                            style: OutlinedButton.styleFrom(
                                                              foregroundColor: AppColors.info,
                                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                              textStyle: AppTextStyles.buttonSmall,
                                                              side: BorderSide(color: AppColors.info.withValues(alpha: 0.3)),
                                                            ),
                                                          ),
                                                        ],
                                                        if (order['status'] == 'CONFIRMED' && !isPurchase) ...[
                                                          OutlinedButton.icon(
                                                            onPressed: () => _transition(order['id'], docType, 'deliver'),
                                                            icon: const Icon(Icons.local_shipping_outlined, size: 14),
                                                            label: const Text('Deliver'),
                                                            style: OutlinedButton.styleFrom(
                                                              foregroundColor: AppColors.info,
                                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                              textStyle: AppTextStyles.buttonSmall,
                                                              side: BorderSide(color: AppColors.info.withValues(alpha: 0.3)),
                                                            ),
                                                          ),
                                                        ],
                                                        if (order['status'] == 'DELIVERED' && !isPurchase) ...[
                                                          OutlinedButton.icon(
                                                            onPressed: () => _transition(order['id'], docType, 'convert'),
                                                            icon: const Icon(Icons.swap_horiz_outlined, size: 14),
                                                            label: const Text('Convert to Inv.'),
                                                            style: OutlinedButton.styleFrom(
                                                              foregroundColor: AppColors.brandNavy,
                                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                              textStyle: AppTextStyles.buttonSmall,
                                                              side: BorderSide(color: AppColors.brandNavy.withValues(alpha: 0.3)),
                                                            ),
                                                          ),
                                                        ],
                                                        if (order['status'] != 'CANCELLED' && order['status'] != 'RECEIVED' && order['status'] != 'DELIVERED') ...[
                                                          const SizedBox(width: 8),
                                                          OutlinedButton.icon(
                                                            onPressed: () => _cancelOrder(order['id'], docType),
                                                            icon: const Icon(Icons.cancel_outlined, size: 14),
                                                            label: const Text('Cancel'),
                                                            style: OutlinedButton.styleFrom(
                                                              foregroundColor: AppColors.error,
                                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                              textStyle: AppTextStyles.buttonSmall,
                                                              side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
                                  vertical: 12,
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
                                              _selectedIds.length == filteredOrders.length
                                                  ? Icons.check_circle
                                                  : Icons.circle_outlined,
                                              size: 22,
                                              color: _selectedIds.length == filteredOrders.length
                                                  ? AppColors.brandNavy
                                                  : AppColors.textMuted,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Select All',
                                              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        '${_selectedIds.length} selected',
                                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                      ),
                                      const Spacer(),
                                      OutlinedButton.icon(
                                        onPressed: _clearSelection,
                                        icon: const Icon(Icons.close, size: 14),
                                        label: const Text('Cancel'),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          textStyle: AppTextStyles.buttonSmall,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: _bulkDelete,
                                        icon: const Icon(Icons.cancel_outlined, size: 14),
                                        label: const Text('Cancel Selected'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.error,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          textStyle: AppTextStyles.buttonSmall,
                                          side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                                        ),
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
