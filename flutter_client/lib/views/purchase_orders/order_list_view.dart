import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/purchase_orders/purchase_order_form_view.dart';
import 'package:flutter_client/core/print_share_helper.dart';

class OrderListView extends StatefulWidget {
  const OrderListView({super.key});

  @override
  State<OrderListView> createState() => _OrderListViewState();
}

class _OrderListViewState extends State<OrderListView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _purchaseOrders = [];
  List<dynamic> _salesOrders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetch();
  }

  void _fetch() async {
    setState(() => _isLoading = true);
    final po = await context.read<DocumentProvider>().fetchPurchaseOrders();
    final so = await context.read<DocumentProvider>().fetchSalesOrders();
    if (mounted) {
      setState(() {
        _purchaseOrders = po;
        _salesOrders = so;
        _isLoading = false;
      });
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
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: AppColors.bgSurface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Purchase Orders'),
              Tab(text: 'Sales Orders'),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPOForm(type: _tabController.index == 0 ? 'PO' : 'SO'),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading orders...')
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_purchaseOrders, 'PO'),
                _buildList(_salesOrders, 'SO'),
              ],
            ),
    );
  }

  Widget _buildList(List<dynamic> list, String type) {
    final isMobile = AdaptiveLayout.isMobile(context);
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.shopping_cart_outlined,
        title: 'No ${type}s',
        subtitle: '${type}s will appear here once created',
      );
    }
    return ListView.separated(
      padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
      itemCount: list.length,
      separatorBuilder: (context, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final order = list[i];
        final numVal = type == 'PO' ? order['po_number'] : order['so_number'];
        return AppCard(
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
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.share_outlined, size: 16),
                        onPressed: () {
                          PrintShareHelper.showShareSheet(
                            context,
                            docLabel: type == 'PO' ? 'Purchase Order' : 'Sales Order',
                            docNumber: numVal?.toString() ?? 'N/A',
                            docType: type == 'PO' ? 'purchase-orders' : 'sales-orders',
                            docId: order['id'],
                          );
                        },
                        tooltip: 'Share / Print',
                      ),
                      const SizedBox(width: 4),
                      if (order['status'] == 'DRAFT') ...[
                        OutlinedButton.icon(
                          onPressed: () => _showPOForm(order: order, type: type),
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
                          onPressed: () => _transition(order['id'], type, 'confirm'),
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
                      if (order['status'] == 'CONFIRMED' && type == 'PO') ...[
                        OutlinedButton.icon(
                          onPressed: () => _transition(order['id'], type, 'receive'),
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
                      if (order['status'] == 'CONFIRMED' && type == 'SO') ...[
                        OutlinedButton.icon(
                          onPressed: () => _transition(order['id'], type, 'deliver'),
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
                      if (order['status'] == 'DELIVERED' && type == 'SO') ...[
                        OutlinedButton.icon(
                          onPressed: () => _transition(order['id'], type, 'convert'),
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
                          onPressed: () => _cancelOrder(order['id'], type),
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
        );
      },
    );
  }
}
