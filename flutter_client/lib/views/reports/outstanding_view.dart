import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';

class OutstandingReceivablesView extends StatefulWidget {
  const OutstandingReceivablesView({super.key});

  @override
  State<OutstandingReceivablesView> createState() => _OutstandingReceivablesViewState();
}

class _OutstandingReceivablesViewState extends State<OutstandingReceivablesView> {
  bool _loading = true;
  List<dynamic> _items = [];
  double _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final provider = context.read<AccountingProvider>();
    final result = await provider.fetchOutstandingReceivables();
    setState(() {
      _items = result?['items'] ?? [];
      _total = double.tryParse(result?['total']?.toString() ?? '0') ?? 0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Outstanding Receivables'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _TotalHeader(total: _total, label: 'Total Outstanding'),
                Expanded(
                  child: _items.isEmpty
                      ? const EmptyState(icon: Icons.people_outline, title: 'No outstanding receivables')
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final dueDate = item['due_date'] != null ? DateTime.tryParse(item['due_date']) : null;
                            final isOverdue = dueDate != null && dueDate.isBefore(DateTime.now());
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: ListTile(
                                title: Text(item['contact_name'] ?? 'Unknown'),
                                subtitle: Text('Invoice: ${item['invoice_number']} | Due: ${item['due_date'] ?? 'N/A'}'),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '₹${item['outstanding']?.toString() ?? '0'}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isOverdue ? Colors.red : Colors.orange,
                                      ),
                                    ),
                                    if (isOverdue)
                                      Text(
                                        '${DateTime.now().difference(dueDate).inDays}d overdue',
                                        style: const TextStyle(fontSize: 10, color: Colors.red),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _TotalHeader extends StatelessWidget {
  final double total;
  final String label;
  const _TotalHeader({required this.total, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            '₹${total.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class OutstandingPayablesView extends StatefulWidget {
  const OutstandingPayablesView({super.key});

  @override
  State<OutstandingPayablesView> createState() => _OutstandingPayablesViewState();
}

class _OutstandingPayablesViewState extends State<OutstandingPayablesView> {
  bool _loading = true;
  List<dynamic> _items = [];
  double _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final provider = context.read<AccountingProvider>();
    final result = await provider.fetchOutstandingPayables();
    setState(() {
      _items = result?['items'] ?? [];
      _total = double.tryParse(result?['total']?.toString() ?? '0') ?? 0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Outstanding Payables'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _TotalHeader(total: _total, label: 'Total Payables'),
                Expanded(
                  child: _items.isEmpty
                      ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'No outstanding payables')
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: ListTile(
                                title: Text(item['contact_name'] ?? 'Unknown'),
                                subtitle: Text('Bill: ${item['bill_number']} | Due: ${item['due_date'] ?? 'N/A'}'),
                                trailing: Text(
                                  '₹${item['outstanding']?.toString() ?? '0'}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
