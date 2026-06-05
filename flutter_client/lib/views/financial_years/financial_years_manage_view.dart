import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/financial_year_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class FinancialYearsManageView extends StatefulWidget {
  const FinancialYearsManageView({super.key});

  @override
  State<FinancialYearsManageView> createState() => _FinancialYearsManageViewState();
}

class _FinancialYearsManageViewState extends State<FinancialYearsManageView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FinancialYearProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final provider = context.watch<FinancialYearProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('Financial Years', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        actions: [
          TextButton.icon(
            onPressed: () => _showCreateDialog(context, provider),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create New Year'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandNavy,
              backgroundColor: AppColors.brandNavy.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: provider.isLoading && provider.availableYears.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(provider, isMobile),
    );
  }

  Widget _buildContent(FinancialYearProvider provider, bool isMobile) {
    final years = provider.availableYears;
    if (years.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text('No Financial Years', style: AppTextStyles.h2),
            const SizedBox(height: 8),
            Text('Create your first financial year to get started.', style: AppTextStyles.bodySmall),
            const SizedBox(height: 24),
            ActionButton(
              label: 'Create Financial Year',
              icon: Icons.add,
              tier: ActionTier.safe,
              onPressed: () => _showCreateDialog(context, provider),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
      itemCount: years.length,
      itemBuilder: (context, index) {
        final year = years[index];
        final isActive = provider.activeYear?.id == year.id;
        final statusColor = year.status.color;
        final statusBg = year.status.bgColor;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            child: Container(
              decoration: isActive
                  ? BoxDecoration(
                      border: Border.all(color: AppColors.brandNavy.withValues(alpha: 0.3)),
                      borderRadius: AppRadius.card,
                    )
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Icon(
                              year.isClosedOrLocked ? Icons.lock_outline : Icons.calendar_today_outlined,
                              size: 20,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'FY ${year.name}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: isActive ? AppColors.brandNavy : AppColors.textPrimary,
                                    ),
                                  ),
                                  if (isActive) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.brandNavy.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'ACTIVE',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.brandNavy),
                                      ),
                                    ),
                                  ],
                                  if (year.isCurrent) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: FYStatus.current.bgColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'CURRENT',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: FYStatus.current.color),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                year.dateRange,
                                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            year.status.label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildStat('Transactions', '${year.transactionCount}', Icons.receipt_long_outlined),
                        const SizedBox(width: 24),
                        _buildStat(
                          'Status',
                          year.status.label,
                          year.status == FYStatus.locked ? Icons.lock_outline : Icons.circle_outlined,
                          valueColor: statusColor,
                        ),
                        if (year.closedAt != null) ...[
                          const SizedBox(width: 24),
                          _buildStat(
                            'Closed',
                            DateFormat('dd MMM yyyy').format(year.closedAt!),
                            Icons.check_circle_outline,
                          ),
                        ],
                        const Spacer(),
                        if (!isActive && !year.isClosedOrLocked)
                          OutlinedButton(
                            onPressed: () => provider.setActiveYear(year),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.brandNavy,
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            child: const Text('Switch'),
                          ),
                        if (year.status == FYStatus.readyToClose || year.status == FYStatus.current)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ElevatedButton.icon(
                              onPressed: () => _showYearEndDashboard(context, year),
                              icon: const Icon(Icons.lock_clock_outlined, size: 14),
                              label: const Text('Year End'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.warning,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStat(String label, String value, IconData icon, {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context, FinancialYearProvider provider) {
    final nameController = TextEditingController();
    final now = DateTime.now();
    final currentFYStart = now.month >= 4 ? now.year : now.year - 1;
    final nextStart = DateTime(currentFYStart + 1, 4, 1);
    final nextEnd = DateTime(currentFYStart + 2, 3, 31);
    nameController.text = '${nextStart.year}-${((nextStart.year + 1) % 100).toString().padLeft(2, '0')}';

    DateTime startDate = nextStart;
    DateTime endDate = nextEnd;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Create New Financial Year'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Year Name',
                    hintText: 'e.g. 2027-28',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDateField(
                        label: 'Start Date',
                        date: startDate,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: startDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              startDate = picked;
                              endDate = DateTime(picked.year + 1, 3, 31);
                              nameController.text = '${picked.year}-${((picked.year + 1) % 100).toString().padLeft(2, '0')}';
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDateField(
                        label: 'End Date',
                        date: endDate,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: endDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2040),
                          );
                          if (picked != null) {
                            setDialogState(() => endDate = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.infoBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: AppColors.info),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Default: Indian Financial Year (Apr 1 – Mar 31). Opening balances will be carried forward.',
                          style: TextStyle(fontSize: 12, color: AppColors.info),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                final result = await provider.createFinancialYear(
                  name: nameController.text.trim(),
                  startDate: startDate,
                  endDate: endDate,
                );
                if (result != null && ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('FY ${result.name} created successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        child: Text(DateFormat('dd MMM yyyy').format(date)),
      ),
    );
  }

  void _showYearEndDashboard(BuildContext context, FinancialYear year) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _YearEndDashboardScreen(fyId: year.id, fyName: year.name),
      ),
    );
  }
}

class _YearEndDashboardScreen extends StatefulWidget {
  final String fyId;
  final String fyName;
  const _YearEndDashboardScreen({required this.fyId, required this.fyName});

  @override
  State<_YearEndDashboardScreen> createState() => _YearEndDashboardScreenState();
}

class _YearEndDashboardScreenState extends State<_YearEndDashboardScreen> {
  YearEndDashboard? _dashboard;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final provider = context.read<FinancialYearProvider>();
    final data = await provider.loadDashboard(widget.fyId);
    setState(() {
      _dashboard = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text('Year End — FY ${widget.fyName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _dashboard == null
              ? const Center(child: Text('Failed to load dashboard'))
              : _buildDashboard(),
    );
  }

  Widget _buildDashboard() {
    final d = _dashboard!;
    final fy = d.financialYear;

    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: d.closingAllowed ? AppColors.successBg : AppColors.warningBg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Icon(
                            d.closingAllowed ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                            size: 28,
                            color: d.closingAllowed ? AppColors.success : AppColors.warning,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('FY ${fy.name}', style: AppTextStyles.h1),
                            const SizedBox(height: 4),
                            Text(fy.dateRange, style: AppTextStyles.bodySmall),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${d.readinessScore}%',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: d.closingAllowed ? AppColors.success : AppColors.warning,
                            ),
                          ),
                          Text(
                            'Readiness',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Checklist
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Closing Readiness Checklist', style: AppTextStyles.h2),
                      const SizedBox(height: 16),
                      _buildChecklistItem('Trial Balance Balanced', d.trialBalanceBalanced),
                      _buildChecklistItem('No Draft Documents', d.unpostedDocumentsCount == 0),
                      _buildChecklistItem('Period Not Already Closed', fy.status != FYStatus.locked),
                      const Divider(height: 24),
                      if (d.netProfit != 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Net Profit:', style: TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              AmountFormat.format(d.netProfit),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: d.netProfit >= 0 ? AppColors.success : AppColors.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (d.unpostedDocumentsCount > 0) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.warningBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${d.unpostedDocumentsCount} draft document(s) pending:',
                                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.warning),
                              ),
                              const SizedBox(height: 8),
                              ...d.unpostedDocuments.map((doc) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '• ${doc['document_type']} #${doc['document_number']} — ${AmountFormat.format(doc['amount'] ?? 0)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              )),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Blocking Items
              if (d.blockingItems.isNotEmpty) ...[
                AppCard(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                            const SizedBox(width: 8),
                            Text('Blocking Issues', style: AppTextStyles.h2),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...d.blockingItems.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.close, size: 14, color: AppColors.error),
                              const SizedBox(width: 8),
                              Expanded(child: Text(item, style: const TextStyle(fontSize: 13))),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Close Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: d.closingAllowed
                      ? () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Confirm Year End Close'),
                              content: Text(
                                'This will close FY ${fy.name} permanently. This action is irreversible.',
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                                  child: const Text('Close Year'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true && mounted) {
                            final provider = context.read<FinancialYearProvider>();
                            final result = await provider.closeFinancialYear(widget.fyId);
                            if (result != null && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('FY ${fy.name} closed successfully'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                              Navigator.pop(context);
                            }
                          }
                        }
                      : null,
                  icon: const Icon(Icons.lock_outlined, size: 18),
                  label: Text(d.closingAllowed ? 'Close Financial Year' : 'Cannot Close — Fix Issues First'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.textMuted.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChecklistItem(String label, bool passed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: passed ? AppColors.successBg : AppColors.errorBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Icon(
                passed ? Icons.check : Icons.close,
                size: 14,
                color: passed ? AppColors.success : AppColors.error,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: passed ? AppColors.textPrimary : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}
