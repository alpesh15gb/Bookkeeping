import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/cash_book_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:intl/intl.dart';

class CashBookView extends StatefulWidget {
  const CashBookView({super.key});

  @override
  State<CashBookView> createState() => _CashBookViewState();
}

class _CashBookViewState extends State<CashBookView> {
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);

    _startCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(startOfMonth));
    _endCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(endOfMonth));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (date != null) {
      setState(() {
        ctrl.text = DateFormat('yyyy-MM-dd').format(date);
      });
      _fetchData();
    }
  }

  void _fetchData() {
    context.read<CashBookProvider>().fetchCashBook(_startCtrl.text, _endCtrl.text);
  }

  Future<void> _downloadExcel() async {
    final token = ApiClient.accessToken ?? '';
    final tenantId = ApiClient.tenantId ?? '';
    final url = Uri.parse(
      '${ApiClient.baseUrl}/reports/cash-book/excel'
      '?start_date=${_startCtrl.text}'
      '&end_date=${_endCtrl.text}'
      '&token=$token&tenant_id=$tenantId',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _downloadPdf() async {
    final token = ApiClient.accessToken ?? '';
    final tenantId = ApiClient.tenantId ?? '';
    final url = Uri.parse(
      '${ApiClient.baseUrl}/reports/cash-book/pdf'
      '?start_date=${_startCtrl.text}'
      '&end_date=${_endCtrl.text}'
      '&token=$token&tenant_id=$tenantId',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CashBookProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Cash Book Report'),
        actions: [
          if (provider.data != null) ...[
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
          preferredSize: const Size.fromHeight(60),
          child: Container(
            color: AppColors.bgSurface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startCtrl,
                    decoration: const InputDecoration(
                      labelText: 'From Date',
                      isDense: true,
                      prefixIcon: Icon(Icons.calendar_today_outlined, size: 14),
                    ),
                    readOnly: true,
                    onTap: () => _pickDate(_startCtrl),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _endCtrl,
                    decoration: const InputDecoration(
                      labelText: 'To Date',
                      isDense: true,
                      prefixIcon: Icon(Icons.calendar_today_outlined, size: 14),
                    ),
                    readOnly: true,
                    onTap: () => _pickDate(_endCtrl),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: provider.isLoading
          ? const LoadingState(message: 'Generating Cash Book...')
          : provider.error != null
              ? ErrorState(message: provider.error!, onRetry: _fetchData)
              : provider.data == null
                  ? const Center(child: Text('No data available'))
                  : _buildBody(provider.data!),
    );
  }

  Widget _buildBody(dynamic data) {
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 800) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTable(data.inflows, 'Cash Inflow')),
                    const SizedBox(width: 16),
                    Expanded(child: _buildTable(data.outflows, 'Cash Outflow')),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildTable(data.inflows, 'Cash Inflow'),
                    const SizedBox(height: 16),
                    _buildTable(data.outflows, 'Cash Outflow'),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'Cash Book Summary',
                  items: [
                    {'label': 'Opening Balance', 'value': data.openingBalance},
                    {'label': 'Cash Inflow', 'value': data.summary.cashInflow},
                    {'label': 'Cash Outflow', 'value': data.summary.cashOutflow},
                    {'label': 'Closing Balance', 'value': data.summary.closingBalance},
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Tax Summary',
                  items: [
                    {'label': 'Tax Received', 'value': data.taxSummary.taxReceived},
                    {'label': 'Tax Paid', 'value': data.taxSummary.taxPaid},
                    {'label': 'Tax Payable', 'value': data.taxSummary.taxPayable},
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<dynamic> rows, String title) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: AppTextStyles.labelMedium),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppColors.bgLight),
              dataRowMinHeight: 40,
              dataRowMaxHeight: 50,
              columns: const [
                DataColumn(label: Text('Date', style: AppTextStyles.caption)),
                DataColumn(label: Text('Details', style: AppTextStyles.caption)),
                DataColumn(label: Text('Inv Amt', style: AppTextStyles.caption), numeric: true),
                DataColumn(label: Text('Tax/GST', style: AppTextStyles.caption), numeric: true),
                DataColumn(label: Text('Amount', style: AppTextStyles.caption), numeric: true),
              ],
              rows: rows.map<DataRow>((row) {
                return DataRow(
                  cells: [
                    DataCell(Text(row.date, style: AppTextStyles.bodySmall)),
                    DataCell(Text(row.transactionDetails, style: AppTextStyles.bodySmall)),
                    DataCell(Text(row.invoiceAmount != null ? row.invoiceAmount!.toStringAsFixed(2) : '-', style: AppTextStyles.numeric)),
                    DataCell(Text(row.taxAmount != null ? row.taxAmount!.toStringAsFixed(2) : '-', style: AppTextStyles.numeric)),
                    DataCell(Text(row.amount.toStringAsFixed(2), style: AppTextStyles.numeric)),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({required String title, required List<Map<String, dynamic>> items}) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.labelSmall),
          const SizedBox(height: 12),
          ...items.map((item) {
            return SummaryRow(
              label: item['label'] as String,
              value: '₹${(item['value'] as double).toStringAsFixed(2)}',
            );
          }),
        ],
      ),
    );
  }
}
