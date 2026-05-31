import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/providers/contact_provider.dart';
import 'package:flutter_client/models/contact.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class PartyStatementView extends StatefulWidget {
  const PartyStatementView({super.key});

  @override
  State<PartyStatementView> createState() => _PartyStatementViewState();
}

class _PartyStatementViewState extends State<PartyStatementView> {
  ContactModel? _selectedContact;
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;

  bool _isLoading = false;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    _startCtrl = TextEditingController(text: _fmt(startOfMonth));
    _endCtrl = TextEditingController(text: _fmt(now));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactProvider>().fetchContacts();
    });
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = DateTime.tryParse(isStart ? _startCtrl.text : _endCtrl.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date != null) {
      final formatted = _fmt(date);
      setState(() {
        if (isStart) {
          _startCtrl.text = formatted;
        } else {
          _endCtrl.text = formatted;
        }
      });
    }
  }

  void _fetchStatement() {
    if (_selectedContact == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    context
        .read<AccountingProvider>()
        .fetchPartyStatement(
          _selectedContact!.id,
          _startCtrl.text,
          _endCtrl.text,
        )
        .then((result) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (result != null) {
            _data = result;
          } else {
            _error = 'Failed to load Party Statement';
          }
        });
      }
    });
  }

  Future<void> _downloadPdf() async {
    if (_selectedContact == null) return;
    final token = ApiClient.accessToken ?? '';
    final tenantId = ApiClient.tenantId ?? '';
    final url = Uri.parse(
      '${ApiClient.baseUrl}/reports/party-statement/pdf'
      '?contact_id=${_selectedContact!.id}'
      '&start_date=${_startCtrl.text}'
      '&end_date=${_endCtrl.text}'
      '&token=$token&tenant_id=$tenantId',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _downloadExcel() async {
    if (_selectedContact == null) return;
    final token = ApiClient.accessToken ?? '';
    final tenantId = ApiClient.tenantId ?? '';
    final url = Uri.parse(
      '${ApiClient.baseUrl}/reports/party-statement/excel'
      '?contact_id=${_selectedContact!.id}'
      '&start_date=${_startCtrl.text}'
      '&end_date=${_endCtrl.text}'
      '&token=$token&tenant_id=$tenantId',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final contacts = context.watch<ContactProvider>().contacts;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Party Statement'),
        actions: [
          if (_data != null) ...[
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
      ),
      body: Column(
        children: [
          // Filters bar
          Container(
            color: AppColors.bgSurface,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: 12,
            ),
            child: isMobile
                ? Column(
                    children: [
                      _buildContactDropdown(contacts),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _buildDateField('From', _startCtrl, () => _pickDate(isStart: true))),
                          const SizedBox(width: 10),
                          Expanded(child: _buildDateField('To', _endCtrl, () => _pickDate(isStart: false))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _selectedContact == null ? null : _fetchStatement,
                          icon: const Icon(Icons.search, size: 16),
                          label: const Text('View Statement'),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(flex: 3, child: _buildContactDropdown(contacts)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildDateField('From', _startCtrl, () => _pickDate(isStart: true))),
                      const SizedBox(width: 12),
                      Expanded(child: _buildDateField('To', _endCtrl, () => _pickDate(isStart: false))),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _selectedContact == null ? null : _fetchStatement,
                        icon: const Icon(Icons.search, size: 16),
                        label: const Text('View Statement'),
                      ),
                    ],
                  ),
          ),

          // Body
          Expanded(
            child: _isLoading
                ? const LoadingState(message: 'Generating Party Statement...')
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _fetchStatement)
                    : _data != null
                        ? _buildStatementBody(isMobile)
                        : const EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: 'Select a Party',
                            subtitle: 'Choose a contact and date range to view their statement',
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactDropdown(List<ContactModel> contacts) {
    return DropdownButtonFormField<ContactModel>(
      initialValue: _selectedContact,
      isDense: true,
      decoration: const InputDecoration(
        labelText: 'Select Party',
        isDense: true,
        prefixIcon: Icon(Icons.people_outline, size: 16),
      ),
      items: contacts.map((c) {
        return DropdownMenuItem(
          value: c,
          child: Text(
            '${c.name} (${c.contactType})',
            style: AppTextStyles.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (val) => setState(() => _selectedContact = val),
    );
  }

  Widget _buildDateField(String label, TextEditingController ctrl, VoidCallback onTap) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        prefixIcon: const Icon(Icons.calendar_today_outlined, size: 14),
      ),
      readOnly: true,
      onTap: onTap,
    );
  }

  Widget _buildStatementBody(bool isMobile) {
    final ledger = _data!['ledger'] as List? ?? [];
    final summary = _data!['summary'] as Map<String, dynamic>? ?? {};
    final contactName = _data!['contact_name'] ?? '';
    final contactType = _data!['contact_type'] ?? '';
    final address = _data!['address'] ?? '';
    final gstin = _data!['gstin'] ?? '';

    final openingBalance = double.tryParse((summary['opening_balance'] ?? 0).toString()) ?? 0.0;
    final totalSales = double.tryParse((summary['total_sales'] ?? 0).toString()) ?? 0.0;
    final totalReceipts = double.tryParse((summary['total_receipts'] ?? 0).toString()) ?? 0.0;
    final totalPurchases = double.tryParse((summary['total_purchases'] ?? 0).toString()) ?? 0.0;
    final totalPayments = double.tryParse((summary['total_payments'] ?? 0).toString()) ?? 0.0;
    final closingOutstanding = double.tryParse((summary['closing_outstanding'] ?? 0).toString()) ?? 0.0;

    return SingleChildScrollView(
      padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Party Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(contactName, style: AppTextStyles.h2),
                    ),
                    StatusBadge.fromContactType(contactType),
                  ],
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(address, style: AppTextStyles.bodySmall),
                ],
                if (gstin.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('GSTIN: $gstin', style: AppTextStyles.caption),
                ],
                const SizedBox(height: 4),
                Text(
                  '${_startCtrl.text} to ${_endCtrl.text}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Summary Cards
          _buildSummaryRow(
            openingBalance,
            totalSales,
            totalReceipts,
            totalPurchases,
            totalPayments,
            closingOutstanding,
            isMobile,
          ),
          const SizedBox(height: 16),

          // Ledger Table
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: Text('Date', style: AppTextStyles.labelSmall)),
                  DataColumn(label: Text('Particulars', style: AppTextStyles.labelSmall)),
                  DataColumn(label: Text('Voucher Type', style: AppTextStyles.labelSmall)),
                  DataColumn(label: Text('Voucher No.', style: AppTextStyles.labelSmall)),
                  DataColumn(label: Text('Debit', style: AppTextStyles.labelSmall), numeric: true),
                  DataColumn(label: Text('Credit', style: AppTextStyles.labelSmall), numeric: true),
                  DataColumn(label: Text('Balance', style: AppTextStyles.labelSmall)),
                ],
                rows: ledger.map((row) {
                  final debit = row['debit'];
                  final credit = row['credit'];
                  final isOpening = row['voucher_type'] == 'Opening';
                  final isClosing = row['particulars'] == 'Closing Balance';
                  final isHighlight = isOpening || isClosing;

                  return DataRow(
                    color: isHighlight
                        ? WidgetStateProperty.all(AppColors.brandNavy.withValues(alpha: 0.04))
                        : null,
                    cells: [
                      DataCell(Text(
                        row['date'] ?? '',
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: isHighlight ? FontWeight.w600 : FontWeight.w400,
                        ),
                      )),
                      DataCell(Text(
                        row['particulars'] ?? '',
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: isHighlight ? FontWeight.w600 : FontWeight.w400,
                        ),
                      )),
                      DataCell(Text(
                        row['voucher_type'] ?? '',
                        style: AppTextStyles.caption,
                      )),
                      DataCell(Text(
                        row['voucher_no'] ?? '',
                        style: AppTextStyles.caption,
                      )),
                      DataCell(Text(
                        debit != null ? '₹${_parseAmount(debit)}' : '-',
                        style: AppTextStyles.amountSmall,
                        textAlign: TextAlign.right,
                      )),
                      DataCell(Text(
                        credit != null ? '₹${_parseAmount(credit)}' : '-',
                        style: AppTextStyles.amountSmall,
                        textAlign: TextAlign.right,
                      )),
                      DataCell(Text(
                        row['balance'] ?? '',
                        style: AppTextStyles.amountSmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    double opening,
    double sales,
    double receipts,
    double purchases,
    double payments,
    double closing,
    bool isMobile,
  ) {
    final items = [
      ('Opening Balance', opening),
      ('Total Sales', sales),
      ('Total Receipts', receipts),
      ('Total Purchases', purchases),
      ('Total Payments', payments),
      ('Closing Outstanding', closing),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items.map((item) {
        final isClosing = item.$1 == 'Closing Outstanding';
        return Container(
          width: isMobile ? double.infinity : 170,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: AppRadius.card,
            border: Border.all(
              color: isClosing ? AppColors.goldAccent : AppColors.border,
              width: isClosing ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.$1, style: AppTextStyles.caption),
              const SizedBox(height: 6),
              Text(
                AmountFormat.format(item.$2),
                style: isClosing ? AppTextStyles.amountLarge.copyWith(color: AppColors.brandNavy) : AppTextStyles.amount,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _parseAmount(dynamic value) {
    final num = double.tryParse(value.toString()) ?? 0.0;
    return AmountFormat.format(num).replaceFirst('₹', '');
  }
}
