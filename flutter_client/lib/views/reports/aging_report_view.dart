import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_client/core/api_client.dart';
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

  Future<void> _downloadPdf() async {
    final token = ApiClient.accessToken ?? '';
    final tenantId = ApiClient.tenantId ?? '';
    final type = _tabController.index == 0 ? 'receivables' : 'payables';
    final url = Uri.parse(
      '${ApiClient.baseUrl}/reports/aging/$type/pdf'
      '?as_of_date=${_dateCtrl.text}'
      '&token=$token&tenant_id=$tenantId',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _downloadExcel() async {
    final token = ApiClient.accessToken ?? '';
    final tenantId = ApiClient.tenantId ?? '';
    final type = _tabController.index == 0 ? 'receivables' : 'payables';
    final url = Uri.parse(
      '${ApiClient.baseUrl}/reports/aging/$type/excel'
      '?as_of_date=${_dateCtrl.text}'
      '&token=$token&tenant_id=$tenantId',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }


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
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
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
        actions: [
          if (_arData != null || _apData != null) ...[
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
              tooltip: 'Download PDF',
              onPressed: _downloadPdf,
            ),
            IconButton(
              icon: const Icon(Icons.table_chart_outlined, size: 20),
              tooltip: 'Download Excel',
              onPressed: _downloadExcel,
            ),
          ],
        ],
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
                  onTap: (_) {
                    // Re-fetch on tab change to ensure fresh data
                    if (!_isLoading) _fetchReports();
                  },
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
    final items = data['lines'] is List ? data['lines'] as List : [];
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
                  final total = double.tryParse((item['total_outstanding'] ?? item['total'] ?? 0).toString()) ?? 0.0;
                  final buckets = item['buckets'] is List ? item['buckets'] as List : [];
                  double b1 = 0, b2 = 0, b3 = 0, b4 = 0;
                  for (final bucket in buckets) {
                    final amount = double.tryParse((bucket['amount'] ?? 0).toString()) ?? 0.0;
                    final label = (bucket['label'] ?? '').toString().toLowerCase();
                    if (label.contains('0-30') || label.contains('0–30')) {
                      b1 = amount;
                    } else if (label.contains('31-60') || label.contains('31–60')) {
                      b2 = amount;
                    } else if (label.contains('61-90') || label.contains('61–90')) {
                      b3 = amount;
                    } else {
                      b4 += amount;
                    }
                  }

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
