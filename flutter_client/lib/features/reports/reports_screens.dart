import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/sales_analytics_provider.dart';
import '../../../providers/eway_bill_provider.dart';
import '../../../providers/misc_provider.dart';
import '../../../providers/accounting_provider.dart';

String _formatAmount(dynamic amount) {
  final val = double.tryParse((amount ?? 0).toString()) ?? 0.0;
  if (val >= 10000000) return '₹${(val / 10000000).toStringAsFixed(1)}Cr';
  if (val >= 100000) return '₹${(val / 100000).toStringAsFixed(1)}L';
  if (val >= 1000) return '₹${(val / 1000).toStringAsFixed(1)}K';
  return '₹${val.toStringAsFixed(0)}';
}

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

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reports & Compliance', style: AppTypography.headlineLarge),
          const SizedBox(height: AppSpacing.sectionGap),
          _buildSection('FINANCIAL REPORTS', [
            _buildReportCard(Icons.balance, 'Trial Balance', 'View account balances', () => context.go('/chart-of-accounts')),
            _buildReportCard(Icons.account_balance, 'Balance Sheet', 'Assets, liabilities, equity', () => context.go('/chart-of-accounts')),
            _buildReportCard(Icons.trending_up, 'Profit & Loss', 'Revenue and expenses', () => context.go('/chart-of-accounts')),
            _buildReportCard(Icons.account_balance_wallet, 'Cash Flow', 'Money in and out', () => context.go('/cash-book')),
          ]),
          const SizedBox(height: AppSpacing.sectionGap),
          _buildSection('COMPLIANCE', [
            _buildReportCard(Icons.description, 'GST Returns', 'GSTR-1, GSTR-3B', () => context.go('/gst-returns')),
            _buildReportCard(Icons.local_shipping, 'E-Way Bills', 'Generate and manage', () => context.go('/eway-bills')),
          ]),
          const SizedBox(height: AppSpacing.sectionGap),
          _buildSection('PARTY REPORTS', [
            _buildReportCard(Icons.assessment, 'Aging Report', 'Receivables and payables', () {}),
            _buildReportCard(Icons.receipt, 'Party Statement', 'Account statements', () {}),
            _buildReportCard(Icons.people, 'Outstanding', 'Receivables and payables', () {}),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> cards) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelMedium.copyWith(color: AppColors.gray500)),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: cards,
        ),
      ],
    );
  }

  Widget _buildReportCard(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return AppCard(
      width: 250,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32, color: AppColors.primary),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: AppTypography.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle, style: AppTypography.bodySmall.copyWith(color: AppColors.gray500)),
        ],
      ),
    );
  }
}

class SalesAnalyticsScreen extends StatefulWidget {
  const SalesAnalyticsScreen({super.key});
  @override
  State<SalesAnalyticsScreen> createState() => _SalesAnalyticsScreenState();
}

class _SalesAnalyticsScreenState extends State<SalesAnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesAnalyticsProvider>().fetchAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SalesAnalyticsProvider>();
    final isLoading = provider.isLoading;
    final customerWise = provider.customerWise;

    double totalRevenue = 0;
    int totalInvoices = 0;
    Set<String> customers = {};
    for (final c in customerWise) {
      final map = c is Map<String, dynamic> ? c : <String, dynamic>{};
      totalRevenue += double.tryParse((map['total_amount'] ?? map['total'] ?? 0).toString()) ?? 0.0;
      totalInvoices += int.tryParse((map['invoice_count'] ?? 0).toString()) ?? 0;
      if (map['contact_name'] != null) customers.add(map['contact_name'].toString());
    }
    final avgOrder = totalInvoices > 0 ? totalRevenue / totalInvoices : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Sales Analytics', style: AppTypography.headlineLarge),
            const Spacer(),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (isLoading)
          const Center(child: CircularProgressIndicator())
        else ...[
          Row(
            children: [
              Expanded(child: AppKpiCard(icon: Icons.trending_up, label: 'TOTAL REVENUE', value: _formatAmount(totalRevenue), iconColor: AppColors.success)),
              const SizedBox(width: AppSpacing.kpiGap),
              Expanded(child: AppKpiCard(icon: Icons.receipt, label: 'INVOICES', value: '$totalInvoices', iconColor: AppColors.info)),
              const SizedBox(width: AppSpacing.kpiGap),
              Expanded(child: AppKpiCard(icon: Icons.people, label: 'CUSTOMERS', value: '${customers.length}', iconColor: AppColors.primary)),
              const SizedBox(width: AppSpacing.kpiGap),
              Expanded(child: AppKpiCard(icon: Icons.receipt_long, label: 'AVG ORDER', value: _formatAmount(avgOrder), iconColor: AppColors.warning)),
            ],
          ),
          const SizedBox(height: AppSpacing.sectionGap),
          if (customerWise.isNotEmpty) ...[
            Text('Top Customers', style: AppTypography.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            AppTable(
              columns: const [
                TableColumn(label: 'Customer', width: 250),
                TableColumn(label: 'Invoices', width: 100),
                TableColumn(label: 'Total', width: 150),
              ],
              rows: customerWise.take(10).map((c) {
                final map = c is Map<String, dynamic> ? c : <String, dynamic>{};
                return AppTableRow(
                  cells: [
                    Text(map['contact_name'] ?? '', style: AppTypography.bodyMedium),
                    Text('${map['invoice_count'] ?? 0}', style: AppTypography.bodySmall),
                    Text(_formatAmount(map['total_amount'] ?? map['total']), style: AppTypography.amountTiny),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ],
    );
  }
}

class GstReturnsScreen extends StatefulWidget {
  const GstReturnsScreen({super.key});
  @override
  State<GstReturnsScreen> createState() => _GstReturnsScreenState();
}

class _GstReturnsScreenState extends State<GstReturnsScreen> {
  Map<String, dynamic>? _gstr1;
  Map<String, dynamic>? _gstr3b;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<AccountingProvider>();
      final now = DateTime.now();
      final start = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final end = '${now.year}-${now.month.toString().padLeft(2, '0')}-${DateTime(now.year, now.month + 1, 0).day.toString().padLeft(2, '0')}';
      final gstr1 = await provider.fetchGstr1(start, end);
      final gstr3b = await provider.fetchGstr3b(start, end);
      if (mounted) {
        setState(() {
          _gstr1 = gstr1;
          _gstr3b = gstr3b;
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('GST Returns', style: AppTypography.headlineLarge),
        const SizedBox(height: AppSpacing.lg),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else
          Row(
            children: [
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppSectionHeader(title: 'GSTR-1'),
                      const SizedBox(height: AppSpacing.md),
                      _buildStatusRow('Status', _gstr1 != null ? 'Data Available' : 'No Data', _gstr1 != null ? AppColors.success : AppColors.warning),
                      if (_gstr1 != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _buildStatusRow('Total Invoices', '${_gstr1!['total_invoices'] ?? 0}', AppColors.gray600),
                        const SizedBox(height: AppSpacing.sm),
                        _buildStatusRow('Total Value', _formatAmount(_gstr1!['total_value']), AppColors.gray600),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppSectionHeader(title: 'GSTR-3B'),
                      const SizedBox(height: AppSpacing.md),
                      _buildStatusRow('Status', _gstr3b != null ? 'Data Available' : 'No Data', _gstr3b != null ? AppColors.success : AppColors.warning),
                      if (_gstr3b != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _buildStatusRow('Total Tax', _formatAmount(_gstr3b!['total_tax'] ?? 0), AppColors.gray600),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodySmall),
        Text(value, style: AppTypography.labelMedium.copyWith(color: color)),
      ],
    );
  }
}

class EwayBillsScreen extends StatefulWidget {
  const EwayBillsScreen({super.key});
  @override
  State<EwayBillsScreen> createState() => _EwayBillsScreenState();
}

class _EwayBillsScreenState extends State<EwayBillsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EwayBillProvider>().fetchEwayBills();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EwayBillProvider>();
    final items = provider.ewayBills;
    final isLoading = provider.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('E-Way Bills', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ E-Way Bill', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? AppEmptyState(icon: Icons.local_shipping, title: 'No E-Way Bills', subtitle: 'Generate your first E-Way Bill')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'E-Way Bill #', width: 140),
                        TableColumn(label: 'Invoice #', width: 120),
                        TableColumn(label: 'Customer', width: 180),
                        TableColumn(label: 'Date', width: 100),
                        TableColumn(label: 'Status', width: 100),
                      ],
                      rows: items.map((item) {
                        final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
                        return AppTableRow(
                          cells: [
                            Text(map['eway_bill_number'] ?? '-', style: AppTypography.labelLarge),
                            Text(map['invoice_number'] ?? '', style: AppTypography.bodySmall),
                            Text(map['recipient_name'] ?? map['customer_name'] ?? '', style: AppTypography.bodyMedium),
                            Text(_formatDate(map['generated_date'] ?? ''), style: AppTypography.bodySmall),
                            AppStatusBadge(status: (map['status'] ?? 'ACTIVE') == 'ACTIVE' ? InvoiceStatus.paid : InvoiceStatus.cancelled),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});
  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  List<dynamic> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final result = await context.read<MiscProvider>().fetchAuditLogs();
    if (mounted) {
      setState(() {
        _logs = result != null ? (result['items'] ?? result['data'] ?? []) : [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Audit Log', style: AppTypography.headlineLarge),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _logs.isEmpty
                  ? AppEmptyState(icon: Icons.history, title: 'No audit logs', subtitle: 'Activity will be logged here')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Timestamp', width: 160),
                        TableColumn(label: 'User', width: 150),
                        TableColumn(label: 'Action', width: 120),
                        TableColumn(label: 'Entity', width: 120),
                        TableColumn(label: 'Details', width: 250),
                      ],
                      rows: _logs.map((log) {
                        final map = log is Map<String, dynamic> ? log : <String, dynamic>{};
                        return AppTableRow(
                          cells: [
                            Text(_formatDate(map['created_at'] ?? map['timestamp'] ?? ''), style: AppTypography.bodySmall),
                            Text(map['user_name'] ?? map['user'] ?? '', style: AppTypography.bodyMedium),
                            Text(map['action'] ?? '', style: AppTypography.bodySmall),
                            Text(map['entity_type'] ?? map['entity'] ?? '', style: AppTypography.bodySmall),
                            Text(map['details'] ?? map['description'] ?? '', style: AppTypography.bodySmall, overflow: TextOverflow.ellipsis),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}
