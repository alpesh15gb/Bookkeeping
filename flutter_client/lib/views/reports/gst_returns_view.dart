import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';

class GstReturnsView extends StatefulWidget {
  const GstReturnsView({super.key});

  @override
  State<GstReturnsView> createState() => _GstReturnsViewState();
}

class _GstReturnsViewState extends State<GstReturnsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;

  bool _isLoading = false;
  Map<String, dynamic>? _gstr1Data;
  Map<String, dynamic>? _gstr3bData;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final now = DateTime.now();
    int year = now.year;
    int month = now.month;
    DateTime startQuarter;
    DateTime endQuarter;

    if (month >= 4 && month <= 6) {
      startQuarter = DateTime(year, 4, 1);
      endQuarter = DateTime(year, 6, 30);
    } else if (month >= 7 && month <= 9) {
      startQuarter = DateTime(year, 7, 1);
      endQuarter = DateTime(year, 9, 30);
    } else if (month >= 10 && month <= 12) {
      startQuarter = DateTime(year, 10, 1);
      endQuarter = DateTime(year, 12, 31);
    } else {
      startQuarter = DateTime(year, 1, 1);
      endQuarter = DateTime(year, 3, 31);
    }

    _startCtrl = TextEditingController(
      text: '${startQuarter.year}-${startQuarter.month.toString().padLeft(2, '0')}-${startQuarter.day.toString().padLeft(2, '0')}',
    );
    _endCtrl = TextEditingController(
      text: '${endQuarter.year}-${endQuarter.month.toString().padLeft(2, '0')}-${endQuarter.day.toString().padLeft(2, '0')}',
    );

    _fetchReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date != null) {
      setState(() {
        ctrl.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      });
      _fetchReports();
    }
  }

  void _fetchReports() async {
    setState(() { _isLoading = true; _error = null; });
    final start = _startCtrl.text;
    final end = _endCtrl.text;

    final provider = context.read<AccountingProvider>();
    final results = await Future.wait([
      provider.fetchGstr1(start, end),
      provider.fetchGstr3b(start, end),
    ]);

    if (mounted) {
      setState(() {
        _gstr1Data = results[0];
        _gstr3bData = results[1];
        _isLoading = false;
        if (_gstr1Data == null && _gstr3bData == null) {
          _error = 'Failed to load GST report data';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('GST Returns'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              // Date Range Selectors
              Container(
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
              Container(
                color: AppColors.bgSurface,
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'GSTR-1 (Sales)'),
                    Tab(text: 'GSTR-3B (Summary)'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const LoadingState(message: 'Generating GST Reports...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _fetchReports)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildGstr1View(),
                    _buildGstr3bView(),
                  ],
                ),
    );
  }

  Widget _buildGstr1View() {
    if (_gstr1Data == null) return const Center(child: Text('No GSTR-1 data available'));
    final b2b = _gstr1Data!['b2b'] as List? ?? [];
    final b2cs = _gstr1Data!['b2cs'] as List? ?? [];
    final hsn = _gstr1Data!['hsn_summary'] as List? ?? [];

    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        // B2B Section
        _buildSectionCard(
          title: 'B2B Supplies (Registered Customers)',
          count: b2b.length,
          child: b2b.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('No registered supplies', style: AppTextStyles.caption))
              : Column(
                  children: b2b.map((item) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item['customer_name'] ?? 'Customer', style: AppTextStyles.bodyMedium),
                      subtitle: Text('GSTIN: ${item['customer_gstin'] ?? "N/A"}', style: AppTextStyles.caption),
                      trailing: Text('₹${double.parse((item['taxable_value'] ?? 0).toString()).toStringAsFixed(2)}', style: AppTextStyles.numeric),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 16),

        // B2CS Section
        _buildSectionCard(
          title: 'B2CS Supplies (Consumer Sales)',
          count: b2cs.length,
          child: b2cs.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('No consumer supplies', style: AppTextStyles.caption))
              : Column(
                  children: b2cs.map((item) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Place of Supply: ${item['pos_state'] ?? "Local"}', style: AppTextStyles.bodyMedium),
                      trailing: Text('₹${double.parse((item['taxable_value'] ?? 0).toString()).toStringAsFixed(2)}', style: AppTextStyles.numeric),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 16),

        // HSN Summary Section
        _buildSectionCard(
          title: 'HSN Wise Summary',
          count: hsn.length,
          child: hsn.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('No HSN data', style: AppTextStyles.caption))
              : Column(
                  children: hsn.map((item) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('HSN: ${item['hsn_sac'] ?? "N/A"}', style: AppTextStyles.bodyMedium),
                      subtitle: Text('Qty: ${item['quantity'] ?? 0}  —  Rate: ${item['gst_rate']}%', style: AppTextStyles.caption),
                      trailing: Text('₹${double.parse((item['taxable_value'] ?? 0).toString()).toStringAsFixed(2)}', style: AppTextStyles.numeric),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildGstr3bView() {
    if (_gstr3bData == null) return const Center(child: Text('No GSTR-3B data available'));

    final outwardVal = double.tryParse((_gstr3bData!['outward_taxable_supplies']?['taxable_value'] ?? 0).toString()) ?? 0.0;
    final outwardIqst = double.tryParse((_gstr3bData!['outward_taxable_supplies']?['igst_amount'] ?? 0).toString()) ?? 0.0;
    final outwardCgst = double.tryParse((_gstr3bData!['outward_taxable_supplies']?['cgst_amount'] ?? 0).toString()) ?? 0.0;
    final outwardSgst = double.tryParse((_gstr3bData!['outward_taxable_supplies']?['sgst_amount'] ?? 0).toString()) ?? 0.0;

    final itcVal = double.tryParse((_gstr3bData!['eligible_itc']?['taxable_value'] ?? 0).toString()) ?? 0.0;
    final itcIgst = double.tryParse((_gstr3bData!['eligible_itc']?['igst_amount'] ?? 0).toString()) ?? 0.0;
    final itcCgst = double.tryParse((_gstr3bData!['eligible_itc']?['cgst_amount'] ?? 0).toString()) ?? 0.0;
    final itcSgst = double.tryParse((_gstr3bData!['eligible_itc']?['sgst_amount'] ?? 0).toString()) ?? 0.0;

    final netIgst = outwardIqst - itcIgst;
    final netCgst = outwardCgst - itcCgst;
    final netSgst = outwardSgst - itcSgst;

    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        // Outward Supplies Summary Card
        _buildSectionCard(
          title: '3.1 Outward Taxable Supplies (Output Tax)',
          child: Column(
            children: [
              SummaryRow(label: 'Total Taxable Value', value: '₹${outwardVal.toStringAsFixed(2)}'),
              SummaryRow(label: 'Integrated Tax (IGST)', value: '₹${outwardIqst.toStringAsFixed(2)}'),
              SummaryRow(label: 'Central Tax (CGST)', value: '₹${outwardCgst.toStringAsFixed(2)}'),
              SummaryRow(label: 'State/UT Tax (SGST)', value: '₹${outwardSgst.toStringAsFixed(2)}'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ITC Summary Card
        _buildSectionCard(
          title: '4. Eligible Input Tax Credit (ITC)',
          child: Column(
            children: [
              SummaryRow(label: 'Integrated Tax (IGST)', value: '₹${itcIgst.toStringAsFixed(2)}'),
              SummaryRow(label: 'Central Tax (CGST)', value: '₹${itcCgst.toStringAsFixed(2)}'),
              SummaryRow(label: 'State/UT Tax (SGST)', value: '₹${itcSgst.toStringAsFixed(2)}'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Net Payable Card
        _buildSectionCard(
          title: 'Net Tax Payable (Output Tax − ITC)',
          child: Column(
            children: [
              SummaryRow(
                label: 'Integrated Tax (IGST)',
                value: '₹${netIgst.toStringAsFixed(2)}',
                valueColor: netIgst >= 0 ? const Color(0xFFB42318) : const Color(0xFF067647),
              ),
              SummaryRow(
                label: 'Central Tax (CGST)',
                value: '₹${netCgst.toStringAsFixed(2)}',
                valueColor: netCgst >= 0 ? const Color(0xFFB42318) : const Color(0xFF067647),
              ),
              SummaryRow(
                label: 'State/UT Tax (SGST)',
                value: '₹${netSgst.toStringAsFixed(2)}',
                valueColor: netSgst >= 0 ? const Color(0xFFB42318) : const Color(0xFF067647),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({required String title, int? count, required Widget child}) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(title, style: AppTextStyles.labelSmall)),
              if (count != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count items', style: AppTextStyles.caption.copyWith(fontSize: 10)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
