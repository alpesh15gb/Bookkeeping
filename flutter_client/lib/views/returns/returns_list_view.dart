import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/shared/transaction_form_view.dart';

class ReturnsListView extends StatefulWidget {
  const ReturnsListView({super.key});

  @override
  State<ReturnsListView> createState() => _ReturnsListViewState();
}

class _ReturnsListViewState extends State<ReturnsListView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _salesReturns = [];
  List<dynamic> _purchaseReturns = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetch();
  }

  void _fetch() async {
    setState(() => _isLoading = true);
    final sr = await context.read<DocumentProvider>().fetchSalesReturns();
    final pr = await context.read<DocumentProvider>().fetchPurchaseReturns();
    if (mounted) {
      setState(() {
        _salesReturns = sr;
        _purchaseReturns = pr;
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelItem(dynamic item, bool isSales) async {
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel?', message: 'Cancel this return?');
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = isSales
          ? await provider.cancelSalesReturn(item['id'])
          : await provider.cancelPurchaseReturn(item['id']);
      if (success) {
        _fetch();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Cancel failed'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showForm(bool isSales) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReturnsFormView(isSalesReturn: isSales)),
    ).then((_) => _fetch());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Returns'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Sales Returns'),
            Tab(text: 'Purchase Returns'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(_tabController.index == 0),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_salesReturns, true),
                _buildList(_purchaseReturns, false),
              ],
            ),
    );
  }

  Widget _buildList(List<dynamic> items, bool isSales) {
    if (items.isEmpty) return const EmptyState(icon: Icons.assignment_return_outlined, title: 'No returns found');
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isSales ? AppColors.errorBg : AppColors.warningBg,
              child: Icon(isSales ? Icons.arrow_back : Icons.arrow_forward,
                color: isSales ? AppColors.error : AppColors.warning, size: 18),
            ),
            title: Text(item['return_number'] ?? 'N/A'),
            subtitle: Text('${item['contact_name'] ?? 'N/A'} | ${item['issue_date'] ?? ''}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusBadge(label: item['status'] ?? 'DRAFT'),
                if (item['status'] == 'POSTED')
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.error),
                    onPressed: () => _cancelItem(item, isSales),
                  ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ReturnsDetailView(item: item, isSalesReturn: isSales)),
              ).then((_) => _fetch());
            },
          ),
        );
      },
    );
  }
}

class ReturnsFormView extends StatelessWidget {
  final bool isSalesReturn;
  const ReturnsFormView({super.key, required this.isSalesReturn});

  @override
  Widget build(BuildContext context) {
    final title = isSalesReturn ? 'Sales Return' : 'Purchase Return';
    return TransactionFormView(
      config: TransactionConfig(
        title: title,
        contactLabel: isSalesReturn ? 'Customer' : 'Vendor',
        contactType: isSalesReturn ? 'CUSTOMER' : 'VENDOR',
        numberLabel: 'Return Number',
        numberKey: 'return_number',
        isPurchase: !isSalesReturn,
        hasReferenceNo: false,
        hasShippingAddress: false,
        hasLinkedInvoice: false,
        allowScanning: false,
        successMessage: '$title saved successfully',
        onSave: (ctx, payload) async {
          final provider = ctx.read<DocumentProvider>();
          final success = isSalesReturn
              ? await provider.createSalesReturn(payload)
              : await provider.createPurchaseReturn(payload);
          if (!success && ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text(provider.errorMessage ?? 'Failed to save return'),
              backgroundColor: AppColors.error,
            ));
          }
          return success;
        },
        onPreview: null,
      ),
    );
  }
}

class ReturnsDetailView extends StatelessWidget {
  final dynamic item;
  final bool isSalesReturn;
  const ReturnsDetailView({super.key, required this.item, required this.isSalesReturn});

  @override
  Widget build(BuildContext context) {
    final title = isSalesReturn ? 'Sales Return' : 'Purchase Return';
    return Scaffold(
      appBar: AppBar(title: Text('$title Detail')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['return_number'] ?? 'N/A', style: AppTextStyles.h2),
                  const SizedBox(height: 8),
                  InfoRow(label: 'Status', value: item['status'] ?? 'N/A'),
                  InfoRow(label: 'Issue Date', value: item['issue_date'] ?? 'N/A'),
                  InfoRow(label: 'Subtotal', value: '₹${item['subtotal']}'),
                  InfoRow(label: 'Total', value: '₹${item['total']}'),
                  if (item['notes'] != null) InfoRow(label: 'Notes', value: item['notes']),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Line Items', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          ...((item['lines'] as List?) ?? []).map((l) => Card(
            child: ListTile(
              title: Text(l['product_name'] ?? 'Product'),
              subtitle: Text('Qty: ${l['quantity']} @ ₹${l['rate']}'),
              trailing: Text('₹${l['total']}'),
            ),
          )),
        ],
      ),
    );
  }
}
