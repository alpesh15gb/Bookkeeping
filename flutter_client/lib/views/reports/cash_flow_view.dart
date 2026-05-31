import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';

class CashFlowView extends StatefulWidget {
  const CashFlowView({super.key});

  @override
  State<CashFlowView> createState() => _CashFlowViewState();
}

class _CashFlowViewState extends State<CashFlowView> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final provider = context.read<AccountingProvider>();
    final result = await provider.fetchCashFlow(_from, _to);
    setState(() {
      _data = result;
      _loading = false;
    });
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textSecondary = theme.textTheme.bodyMedium?.color?.withOpacity(0.7) ?? Colors.grey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Flow Statement'),
        actions: [
          TextButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range, size: 18),
            label: Text('${_formatDate(_from)} - ${_formatDate(_to)}'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? const EmptyState(message: 'No cash flow data available')
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SummaryCard(data: _data!),
                      const SizedBox(height: 16),
                      _FlowSection(
                        title: 'Operating Activities',
                        items: _data!['operating'] ?? {},
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 16),
                      _FlowSection(
                        title: 'Investing Activities',
                        items: _data!['investing'] ?? {},
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      _FlowSection(
                        title: 'Financing Activities',
                        items: _data!['financing'] ?? {},
                        color: Colors.purple,
                      ),
                    ],
                  ),
                ),
    );
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final opening = double.tryParse(data['opening_balance']?.toString() ?? '0') ?? 0;
    final closing = double.tryParse(data['closing_balance']?.toString() ?? '0') ?? 0;
    final netChange = closing - opening;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _AmountColumn(label: 'Opening Balance', amount: opening, color: Colors.grey),
            ),
            Expanded(
              child: _AmountColumn(label: 'Net Change', amount: netChange, color: netChange >= 0 ? Colors.green : Colors.red),
            ),
            Expanded(
              child: _AmountColumn(label: 'Closing Balance', amount: closing, color: Colors.blue),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountColumn extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  const _AmountColumn({required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: color.withOpacity(0.8))),
        const SizedBox(height: 4),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}

class _FlowSection extends StatelessWidget {
  final String title;
  final Map<String, dynamic> items;
  final Color color;
  const _FlowSection({required this.title, required this.items, required this.color});

  @override
  Widget build(BuildContext context) {
    final inflows = double.tryParse(items['inflows']?.toString() ?? '0') ?? 0;
    final outflows = double.tryParse(items['outflows']?.toString() ?? '0') ?? 0;
    final net = inflows - outflows;

    return Card(
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(Icons.trending_up, color: color, size: 18)),
        subtitle: Text('Net: ₹${net.toStringAsFixed(2)}', style: TextStyle(color: net >= 0 ? Colors.green : Colors.red)),
        children: [
          ListTile(title: const Text('Inflows'), trailing: Text('₹${inflows.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green))),
          ListTile(title: const Text('Outflows'), trailing: Text('₹${outflows.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
  }
}
