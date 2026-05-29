import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';

class AgingReportView extends StatefulWidget {
  const AgingReportView({super.key});

  @override
  State<AgingReportView> createState() => _AgingReportViewState();
}

class _AgingReportViewState extends State<AgingReportView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _dateCtrl;

  bool _isLoading = false;
  Map<String, dynamic>? _arData;
  Map<String, dynamic>? _apData;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final now = DateTime.now();
    _dateCtrl = TextEditingController(
      text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    );

    _fetchReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_dateCtrl.text) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date != null) {
      setState(() {
        _dateCtrl.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      });
      _fetchReports();
    }
  }

  void _fetchReports() async {
    setState(() { _isLoading = true; _error = null; });
    final dateStr = _dateCtrl.text;

    final provider = context.read<AccountingProvider>();
    final results = await Future.wait([
      provider.fetchReceivablesAging(dateStr),
      provider.fetchPayablesAging(dateStr),
    ]);

    if (mounted) {
      setState(() {
        _arData = results[0];
        _apData = results[1];
        _isLoading = false;
        if (_arData == null && _apData == null) {
          _error = 'Failed to generate Aging Report';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Aging Report'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              // As of Date Selector
              Container(
                color: AppColors.bgSurface,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextFormField(
                  controller: _dateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'As of Date',
                    isDense: true,
                    prefixIcon: Icon(Icons.calendar_today_outlined, size: 14),
                  ),
                  readOnly: true,
                  onTap: _pickDate,
                ),
              ),
              Container(
                color: AppColors.bgSurface,
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Receivables (AR)'),
                    Tab(text: 'Payables (AP)'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const LoadingState(message: 'Generating Aging Report...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _fetchReports)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAgingTable(_arData, 'Customers'),
                    _buildAgingTable(_apData, 'Vendors'),
                  ],
                ),
    );
  }

  Widget _buildAgingTable(Map<String, dynamic>? data, String partyLabel) {
    if (data == null) return const Center(child: Text('No data available'));
    final items = data['items'] as List? ?? [];
    if (items.isEmpty) {
      return Center(
        child: Text('All $partyLabel accounts are fully settled.', style: AppTextStyles.bodySmall),
      );
    }

    final totalOutstanding = double.tryParse((data['total_outstanding'] ?? 0).toString()) ?? 0.0;

    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Total Outstanding Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Outstanding', style: AppTextStyles.h3),
                Text('₹${totalOutstanding.toStringAsFixed(2)}', style: AppTextStyles.numericLarge.copyWith(color: AppColors.brandNavy)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Scrollable Table
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 14,
                columns: [
                  DataColumn(label: Text(partyLabel, style: AppTextStyles.labelSmall)),
                  const DataColumn(label: Text('Total', style: AppTextStyles.labelSmall)),
                  const DataColumn(label: Text('0-30 days', style: AppTextStyles.labelSmall)),
                  const DataColumn(label: Text('31-60 days', style: AppTextStyles.labelSmall)),
                  const DataColumn(label: Text('61-90 days', style: AppTextStyles.labelSmall)),
                  const DataColumn(label: Text('91+ days', style: AppTextStyles.labelSmall)),
                ],
                rows: items.map((item) {
                  final contactName = item['contact_name'] ?? 'N/A';
                  final total = double.tryParse((item['total'] ?? 0).toString()) ?? 0.0;
                  final b1 = double.tryParse((item['bucket_0_30'] ?? 0).toString()) ?? 0.0;
                  final b2 = double.tryParse((item['bucket_31_60'] ?? 0).toString()) ?? 0.0;
                  final b3 = double.tryParse((item['bucket_61_90'] ?? 0).toString()) ?? 0.0;
                  final b4 = double.tryParse((item['bucket_91_plus'] ?? 0).toString()) ?? 0.0;

                  return DataRow(
                    cells: [
                      DataCell(Text(contactName, style: AppTextStyles.bodySmall)),
                      DataCell(Text('₹${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      DataCell(Text(b1 > 0 ? '₹${b1.toStringAsFixed(2)}' : '-', style: AppTextStyles.numeric.copyWith(fontSize: 10))),
                      DataCell(Text(b2 > 0 ? '₹${b2.toStringAsFixed(2)}' : '-', style: AppTextStyles.numeric.copyWith(fontSize: 10))),
                      DataCell(Text(b3 > 0 ? '₹${b3.toStringAsFixed(2)}' : '-', style: AppTextStyles.numeric.copyWith(fontSize: 10))),
                      DataCell(Text(b4 > 0 ? '₹${b4.toStringAsFixed(2)}' : '-', style: AppTextStyles.numeric.copyWith(fontSize: 10, color: AppColors.error))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
