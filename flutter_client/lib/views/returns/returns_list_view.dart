import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

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
    if (items.isEmpty) return const EmptyState(message: 'No returns found');
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

class ReturnsFormView extends StatefulWidget {
  final bool isSalesReturn;
  const ReturnsFormView({super.key, required this.isSalesReturn});

  @override
  State<ReturnsFormView> createState() => _ReturnsFormViewState();
}

class _ReturnsFormViewState extends State<ReturnsFormView> {
  final _contactCtrl = TextEditingController();
  DateTime _issueDate = DateTime.now();
  String _posStateCode = '27';
  final List<Map<String, dynamic>> _lines = [];
  final _notesCtrl = TextEditingController();

  Future<void> _save() async {
    if (_contactCtrl.text.isEmpty || _lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill contact and add at least one line item')),
      );
      return;
    }

    final payload = {
      'contact_id': _contactCtrl.text, // TODO: proper contact picker
      'issue_date': '${_issueDate.year}-${_issueDate.month.toString().padLeft(2, '0')}-${_issueDate.day.toString().padLeft(2, '0')}',
      'pos_state_code': _posStateCode,
      'line_items': _lines.map((l) => {
        'product_id': l['product_id'],
        'quantity': l['quantity'],
        'rate': l['rate'],
        'hsn_sac': l['hsn_sac'],
        'gst_rate': l['gst_rate'],
        'description': l['description'],
      }).toList(),
      'notes': _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null,
    };

    final provider = context.read<DocumentProvider>();
    final success = widget.isSalesReturn
        ? await provider.createSalesReturn(payload)
        : await provider.createPurchaseReturn(payload);

    if (success && mounted) {
      Navigator.pop(context);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage ?? 'Failed to create'), backgroundColor: AppColors.error),
      );
    }
  }

  void _addLine() {
    setState(() {
      _lines.add({
        'product_id': '',
        'description': '',
        'quantity': 1.0,
        'rate': 0.0,
        'hsn_sac': '',
        'gst_rate': 0.0,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isSalesReturn ? 'New Sales Return' : 'New Purchase Return';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _contactCtrl,
            decoration: const InputDecoration(labelText: 'Contact ID (paste UUID)'),
          ),
          const SizedBox(height: 12),
          ListTile(
            title: const Text('Issue Date'),
            subtitle: Text('${_issueDate.day}/${_issueDate.month}/${_issueDate.year}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _issueDate, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null) setState(() => _issueDate = d);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(labelText: 'POS State Code'),
            onChanged: (v) => _posStateCode = v,
            controller: TextEditingController(text: _posStateCode),
          ),
          const SizedBox(height: 12),
          TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Line Items', style: AppTextStyles.h3),
              const Spacer(),
              IconButton(icon: const Icon(Icons.add), onPressed: _addLine),
            ],
          ),
          ..._lines.asMap().entries.map((entry) {
            final i = entry.key;
            final line = entry.value;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(labelText: 'Product ID'),
                      onChanged: (v) => line['product_id'] = v,
                    ),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Qty'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => line['quantity'] = double.tryParse(v) ?? 1,
                    ),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Rate'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => line['rate'] = double.tryParse(v) ?? 0,
                    ),
                    TextField(
                      decoration: const InputDecoration(labelText: 'HSN'),
                      onChanged: (v) => line['hsn_sac'] = v,
                    ),
                    TextField(
                      decoration: const InputDecoration(labelText: 'GST %'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => line['gst_rate'] = double.tryParse(v) ?? 0,
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _save, child: Text('Save $title')),
        ],
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
