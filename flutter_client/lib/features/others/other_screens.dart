import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/estimate_provider.dart';
import '../../../providers/credit_note_provider.dart';
import '../../../providers/purchase_order_provider.dart';
import '../../../providers/delivery_challan_provider.dart';
import '../../../providers/inventory_adjustment_provider.dart';
import '../../../providers/document_provider.dart';

String _formatDate(String date) {
  if (date.isEmpty) return '-';
  try {
    final d = DateTime.parse(date);
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}';
  } catch (_) {
    return date;
  }
}

String _formatAmount(dynamic amount) {
  final val = double.tryParse((amount ?? 0).toString()) ?? 0.0;
  if (val >= 10000000) return '₹${(val / 10000000).toStringAsFixed(1)}Cr';
  if (val >= 100000) return '₹${(val / 100000).toStringAsFixed(1)}L';
  if (val >= 1000) return '₹${(val / 1000).toStringAsFixed(1)}K';
  return '₹${val.toStringAsFixed(0)}';
}

InvoiceStatus _parseStatus(String status) {
  switch (status.toUpperCase()) {
    case 'PAID': return InvoiceStatus.paid;
    case 'PARTIAL': return InvoiceStatus.partial;
    case 'OVERDUE': return InvoiceStatus.overdue;
    case 'DRAFT': return InvoiceStatus.draft;
    case 'CANCELLED': return InvoiceStatus.cancelled;
    case 'ISSUED': return InvoiceStatus.paid;
    case 'SENT': return InvoiceStatus.pending;
    case 'ACCEPTED': return InvoiceStatus.paid;
    case 'CONVERTED': return InvoiceStatus.paid;
    default: return InvoiceStatus.pending;
  }
}

class EstimatesScreen extends StatefulWidget {
  const EstimatesScreen({super.key});
  @override
  State<EstimatesScreen> createState() => _EstimatesScreenState();
}

class _EstimatesScreenState extends State<EstimatesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EstimateProvider>().fetchEstimates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EstimateProvider>();
    final items = provider.items;
    final isLoading = provider.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Estimates', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Estimate', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? AppEmptyState(icon: Icons.receipt_long, title: 'No estimates', subtitle: 'Create your first estimate')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Estimate #', width: 130),
                        TableColumn(label: 'Customer', width: 180),
                        TableColumn(label: 'Date', width: 100),
                        TableColumn(label: 'Valid Until', width: 110),
                        TableColumn(label: 'Amount', width: 120),
                        TableColumn(label: 'Status', width: 100),
                      ],
                      rows: items.map((item) {
                        final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
                        return AppTableRow(
                          cells: [
                            Text(map['estimate_number'] ?? map['proforma_number'] ?? '-', style: AppTypography.labelLarge),
                            Text(map['contact_name'] ?? map['customer_name'] ?? '', style: AppTypography.bodyMedium),
                            Text(_formatDate(map['issue_date'] ?? map['date'] ?? ''), style: AppTypography.bodySmall),
                            Text(_formatDate(map['valid_until'] ?? ''), style: AppTypography.bodySmall),
                            Text(_formatAmount(map['total']), style: AppTypography.amountTiny),
                            AppStatusBadge(status: _parseStatus(map['status'] ?? 'DRAFT')),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}

class CreditNotesScreen extends StatefulWidget {
  const CreditNotesScreen({super.key});
  @override
  State<CreditNotesScreen> createState() => _CreditNotesScreenState();
}

class _CreditNotesScreenState extends State<CreditNotesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CreditNoteProvider>().fetchCreditNotes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CreditNoteProvider>();
    final items = provider.items;
    final isLoading = provider.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Credit Notes', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Credit Note', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? AppEmptyState(icon: Icons.receipt_long, title: 'No credit notes', subtitle: 'Create your first credit note')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Note #', width: 130),
                        TableColumn(label: 'Customer', width: 180),
                        TableColumn(label: 'Date', width: 100),
                        TableColumn(label: 'Amount', width: 120),
                        TableColumn(label: 'Status', width: 100),
                      ],
                      rows: items.map((item) {
                        final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
                        return AppTableRow(
                          cells: [
                            Text(map['credit_note_number'] ?? '-', style: AppTypography.labelLarge),
                            Text(map['contact_name'] ?? '', style: AppTypography.bodyMedium),
                            Text(_formatDate(map['issue_date'] ?? ''), style: AppTypography.bodySmall),
                            Text(_formatAmount(map['total']), style: AppTypography.amountTiny),
                            AppStatusBadge(status: _parseStatus(map['status'] ?? 'DRAFT')),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}

class SalesOrdersScreen extends StatefulWidget {
  const SalesOrdersScreen({super.key});
  @override
  State<SalesOrdersScreen> createState() => _SalesOrdersScreenState();
}

class _SalesOrdersScreenState extends State<SalesOrdersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PurchaseOrderProvider>().fetchSalesOrders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PurchaseOrderProvider>();
    final items = provider.items;
    final isLoading = provider.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Sales Orders', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Order', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? AppEmptyState(icon: Icons.shopping_cart, title: 'No sales orders', subtitle: 'Create your first sales order')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Order #', width: 130),
                        TableColumn(label: 'Customer', width: 180),
                        TableColumn(label: 'Date', width: 100),
                        TableColumn(label: 'Amount', width: 120),
                        TableColumn(label: 'Status', width: 100),
                      ],
                      rows: items.map((item) {
                        final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
                        return AppTableRow(
                          cells: [
                            Text(map['order_number'] ?? '-', style: AppTypography.labelLarge),
                            Text(map['contact_name'] ?? '', style: AppTypography.bodyMedium),
                            Text(_formatDate(map['order_date'] ?? ''), style: AppTypography.bodySmall),
                            Text(_formatAmount(map['total']), style: AppTypography.amountTiny),
                            AppStatusBadge(status: _parseStatus(map['status'] ?? 'DRAFT')),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}

class PurchaseOrdersScreen extends StatefulWidget {
  const PurchaseOrdersScreen({super.key});
  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PurchaseOrderProvider>().fetchPurchaseOrders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PurchaseOrderProvider>();
    final items = provider.items;
    final isLoading = provider.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Purchase Orders', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Order', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? AppEmptyState(icon: Icons.shopping_cart, title: 'No purchase orders', subtitle: 'Create your first purchase order')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Order #', width: 130),
                        TableColumn(label: 'Vendor', width: 180),
                        TableColumn(label: 'Date', width: 100),
                        TableColumn(label: 'Amount', width: 120),
                        TableColumn(label: 'Status', width: 100),
                      ],
                      rows: items.map((item) {
                        final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
                        return AppTableRow(
                          cells: [
                            Text(map['order_number'] ?? '-', style: AppTypography.labelLarge),
                            Text(map['contact_name'] ?? '', style: AppTypography.bodyMedium),
                            Text(_formatDate(map['order_date'] ?? ''), style: AppTypography.bodySmall),
                            Text(_formatAmount(map['total']), style: AppTypography.amountTiny),
                            AppStatusBadge(status: _parseStatus(map['status'] ?? 'DRAFT')),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}

class DebitNotesScreen extends StatefulWidget {
  const DebitNotesScreen({super.key});
  @override
  State<DebitNotesScreen> createState() => _DebitNotesScreenState();
}

class _DebitNotesScreenState extends State<DebitNotesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CreditNoteProvider>().fetchDebitNotes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CreditNoteProvider>();
    final items = provider.items;
    final isLoading = provider.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Debit Notes', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Debit Note', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? AppEmptyState(icon: Icons.receipt_long, title: 'No debit notes', subtitle: 'Create your first debit note')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Note #', width: 130),
                        TableColumn(label: 'Vendor', width: 180),
                        TableColumn(label: 'Date', width: 100),
                        TableColumn(label: 'Amount', width: 120),
                        TableColumn(label: 'Status', width: 100),
                      ],
                      rows: items.map((item) {
                        final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
                        return AppTableRow(
                          cells: [
                            Text(map['debit_note_number'] ?? '-', style: AppTypography.labelLarge),
                            Text(map['contact_name'] ?? '', style: AppTypography.bodyMedium),
                            Text(_formatDate(map['issue_date'] ?? ''), style: AppTypography.bodySmall),
                            Text(_formatAmount(map['total']), style: AppTypography.amountTiny),
                            AppStatusBadge(status: _parseStatus(map['status'] ?? 'DRAFT')),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});
  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  List<dynamic> _salesReturns = [];
  List<dynamic> _purchaseReturns = [];
  bool _showSalesReturns = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final docProvider = context.read<DocumentProvider>();
      final salesReturns = await docProvider.fetchSalesReturns();
      final purchaseReturns = await docProvider.fetchPurchaseReturns();
      if (mounted) {
        setState(() {
          _salesReturns = salesReturns;
          _purchaseReturns = purchaseReturns;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _showSalesReturns ? _salesReturns : _purchaseReturns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Returns', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Return', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AppFilterChip(label: 'Sales Returns', count: _salesReturns.length, isSelected: _showSalesReturns, onTap: () => setState(() => _showSalesReturns = true)),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Purchase Returns', count: _purchaseReturns.length, isSelected: !_showSalesReturns, onTap: () => setState(() => _showSalesReturns = false)),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: items.isEmpty
              ? AppEmptyState(icon: Icons.replay, title: 'No returns', subtitle: 'No ${_showSalesReturns ? 'sales' : 'purchase'} returns found')
              : AppTable(
                  columns: const [
                    TableColumn(label: 'Return #', width: 130),
                    TableColumn(label: 'Party', width: 180),
                    TableColumn(label: 'Date', width: 100),
                    TableColumn(label: 'Amount', width: 120),
                    TableColumn(label: 'Status', width: 100),
                  ],
                  rows: items.map((item) {
                    final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
                    return AppTableRow(
                      cells: [
                        Text(map['return_number'] ?? '-', style: AppTypography.labelLarge),
                        Text(map['contact_name'] ?? '', style: AppTypography.bodyMedium),
                        Text(_formatDate(map['return_date'] ?? ''), style: AppTypography.bodySmall),
                        Text(_formatAmount(map['total']), style: AppTypography.amountTiny),
                        AppStatusBadge(status: _parseStatus(map['status'] ?? 'DRAFT')),
                      ],
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

class DeliveryChallansScreen extends StatefulWidget {
  const DeliveryChallansScreen({super.key});
  @override
  State<DeliveryChallansScreen> createState() => _DeliveryChallansScreenState();
}

class _DeliveryChallansScreenState extends State<DeliveryChallansScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeliveryChallanProvider>().fetchChallans();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeliveryChallanProvider>();
    final items = provider.challans;
    final isLoading = provider.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Delivery Challans', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Challan', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? AppEmptyState(icon: Icons.local_shipping, title: 'No delivery challans', subtitle: 'Create your first challan')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Challan #', width: 130),
                        TableColumn(label: 'Customer', width: 180),
                        TableColumn(label: 'Date', width: 100),
                        TableColumn(label: 'Status', width: 100),
                      ],
                      rows: items.map((item) {
                        final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
                        return AppTableRow(
                          cells: [
                            Text(map['challan_number'] ?? '-', style: AppTypography.labelLarge),
                            Text(map['contact_name'] ?? '', style: AppTypography.bodyMedium),
                            Text(_formatDate(map['challan_date'] ?? ''), style: AppTypography.bodySmall),
                            AppStatusBadge(status: _parseStatus(map['status'] ?? 'DRAFT')),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}

class InventoryAdjustmentsScreen extends StatefulWidget {
  const InventoryAdjustmentsScreen({super.key});
  @override
  State<InventoryAdjustmentsScreen> createState() => _InventoryAdjustmentsScreenState();
}

class _InventoryAdjustmentsScreenState extends State<InventoryAdjustmentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryAdjustmentProvider>().fetchAdjustments();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryAdjustmentProvider>();
    final items = provider.adjustments;
    final isLoading = provider.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Inventory Adjustments', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Adjustment', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? AppEmptyState(icon: Icons.inventory, title: 'No adjustments', subtitle: 'Record your first inventory adjustment')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Adjustment #', width: 140),
                        TableColumn(label: 'Date', width: 100),
                        TableColumn(label: 'Product', width: 180),
                        TableColumn(label: 'Qty Change', width: 110),
                        TableColumn(label: 'Reason', width: 150),
                      ],
                      rows: items.map((item) {
                        final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
                        return AppTableRow(
                          cells: [
                            Text(map['adjustment_number'] ?? '-', style: AppTypography.labelLarge),
                            Text(_formatDate(map['adjustment_date'] ?? ''), style: AppTypography.bodySmall),
                            Text(map['product_name'] ?? '', style: AppTypography.bodyMedium),
                            Text('${map['quantity_change'] ?? 0}', style: AppTypography.bodySmall),
                            Text(map['reason'] ?? '', style: AppTypography.bodySmall),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}
