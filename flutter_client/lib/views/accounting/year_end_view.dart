import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/financial_year_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:intl/intl.dart';

class YearEndCloseView extends StatefulWidget {
  const YearEndCloseView({super.key});

  @override
  State<YearEndCloseView> createState() => _YearEndCloseViewState();
}

class _YearEndCloseViewState extends State<YearEndCloseView> {
  int _currentStep = 0;
  YearEndDashboard? _dashboard;
  Map<String, dynamic>? _closeResult;
  String? _localError;
  bool _isPerformingAction = false;
  bool _isLoading = true;
  final _confirmController = TextEditingController();
  bool _confirmEnabled = false;

  @override
  void initState() {
    super.initState();
    _confirmController.addListener(() {
      setState(() {
        _confirmEnabled = _confirmController.text.trim() == 'CLOSE FY ${_dashboard?.financialYear.name ?? ''}';
      });
    });
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _localError = null;
      _dashboard = null;
      _isLoading = true;
    });

    final provider = context.read<FinancialYearProvider>();

    // Wait for FY provider to finish loading if it's in progress
    if (provider.isLoading) {
      // Give it a moment to complete
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // If FY provider hasn't loaded yet, trigger initialization
    if (provider.activeYear == null && !provider.isLoading) {
      await provider.init();
      // Give it a moment to complete
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (provider.activeYear == null && mounted) {
      setState(() {
        _localError = 'No active financial year. Please select or create one.';
        _isLoading = false;
      });
      return;
    }

    if (provider.activeYear == null) return;

    final data = await provider.loadDashboard(provider.activeYear!.id);
    if (data == null && mounted) {
      setState(() {
        _localError = provider.errorMessage ?? 'Failed to load year-end dashboard';
        _isLoading = false;
      });
    } else if (data != null) {
      setState(() {
        _dashboard = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _executeClosing() async {
    setState(() {
      _isPerformingAction = true;
      _localError = null;
    });

    final provider = context.read<FinancialYearProvider>();
    final result = await provider.closeFinancialYear(provider.activeYear!.id);

    setState(() {
      _isPerformingAction = false;
    });

    if (result == null && mounted) {
      setState(() {
        _localError = provider.errorMessage ?? 'Failed to close year end';
      });
    } else if (result != null) {
      setState(() {
        _closeResult = result;
        _currentStep = 3;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: AppColors.bgSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text('Year End Closing & Lock', style: AppTextStyles.h2),
              ),
              if (_currentStep < 3)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _loadDashboard,
                  tooltip: 'Refresh',
                ),
            ],
          ),
        ),
      ),
      body: _isPerformingAction
          ? const LoadingState(message: 'Executing Year End Closing operations...')
          : _buildMainContent(isMobile),
    );
  }

  Widget _buildMainContent(bool isMobile) {
    if (_localError != null && _dashboard == null) {
      return _buildErrorState();
    }
    if (_isLoading || _dashboard == null) {
      return const LoadingState(message: 'Running pre-close audit verification...');
    }
    if (_currentStep == 3) return _buildSuccessScreen();

    return Column(
      children: [
        _buildStepIndicator(),
        Expanded(
          child: SingleChildScrollView(
            padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                child: _buildStepContent(),
              ),
            ),
          ),
        ),
        _buildBottomNavigation(),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: AppCard(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                const SizedBox(height: 16),
                Text('Pre-closure Check Failed', style: AppTextStyles.h2),
                const SizedBox(height: 8),
                Text(_localError!, textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
                const SizedBox(height: 24),
                ActionButton(
                  label: 'Retry Check',
                  icon: Icons.refresh,
                  tier: ActionTier.safe,
                  onPressed: _loadDashboard,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildStepIndicatorNode(0, '1. Readiness Check'),
          _buildStepIndicatorLine(0),
          _buildStepIndicatorNode(1, '2. Closing Preview'),
          _buildStepIndicatorLine(1),
          _buildStepIndicatorNode(2, '3. Lock & Confirm'),
        ],
      ),
    );
  }

  Widget _buildStepIndicatorNode(int index, String label) {
    final isActive = _currentStep == index;
    final isDone = _currentStep > index;
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone ? AppColors.success : (isActive ? AppColors.brandNavy : AppColors.bgLight),
            border: Border.all(color: isActive ? AppColors.brandNavy : AppColors.border),
          ),
          child: Center(
            child: isDone
                ? Icon(Icons.check, size: 16, color: Colors.white)
                : Text('${index + 1}', style: TextStyle(
                    color: isActive ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(
          color: isActive ? AppColors.brandNavy : AppColors.textSecondary,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400, fontSize: 13)),
      ],
    );
  }

  Widget _buildStepIndicatorLine(int fromIndex) {
    return Container(
      width: 40, height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: _currentStep > fromIndex ? AppColors.success : AppColors.border,
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0: return _buildReadinessStep();
      case 1: return _buildPreviewStep();
      case 2: return _buildConfirmStep();
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildReadinessStep() {
    final d = _dashboard!;
    final checks = [
      _CheckItem('Trial Balance Balanced', d.trialBalanceBalanced),
      _CheckItem('No Draft Invoices', !d.unpostedDocuments.any((doc) => doc['document_type'] == 'INVOICE')),
      _CheckItem('No Draft Bills', !d.unpostedDocuments.any((doc) => doc['document_type'] == 'BILL')),
      _CheckItem('No Draft Expenses', !d.unpostedDocuments.any((doc) => doc['document_type'] == 'EXPENSE')),
      _CheckItem('Period Not Already Closed', d.financialYear.status != FYStatus.locked),
    ];
    final passedCount = checks.where((c) => c.passed).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: d.closingAllowed ? AppColors.successBg : AppColors.warningBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      '${d.readinessScore}',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                        color: d.closingAllowed ? AppColors.success : AppColors.warning),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.closingAllowed ? 'Books are ready to close' : 'Issues must be resolved first',
                        style: AppTextStyles.h2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$passedCount of ${checks.length} checks passed',
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Readiness Checklist', style: AppTextStyles.h2),
                const SizedBox(height: 16),
                ...checks.map((check) => _buildCheckItem(check)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckItem(_CheckItem check) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: check.passed ? AppColors.successBg : AppColors.errorBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Icon(check.passed ? Icons.check : Icons.close, size: 14,
                color: check.passed ? AppColors.success : AppColors.error),
            ),
          ),
          const SizedBox(width: 12),
          Text(check.label, style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w500,
            color: check.passed ? AppColors.textPrimary : AppColors.error)),
        ],
      ),
    );
  }

  Widget _buildPreviewStep() {
    final d = _dashboard!;
    final fy = d.financialYear;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  d.netProfit >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  color: d.netProfit >= 0 ? AppColors.success : AppColors.warning,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  d.netProfit >= 0 ? 'Net Profit for the Year' : 'Net Loss for the Year',
                  style: AppTextStyles.h2,
                ),
                const SizedBox(height: 8),
                Text(
                  AmountFormat.format(d.netProfit),
                  style: AppTextStyles.amountLarge.copyWith(
                    color: d.netProfit >= 0 ? AppColors.success : AppColors.warning,
                    fontSize: 32,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'From ${DateFormat('dd-MMM-yyyy').format(fy.startDate)} to ${DateFormat('dd-MMM-yyyy').format(fy.endDate)}',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Closing Journal Entry Preview', style: AppTextStyles.h2),
                const SizedBox(height: 12),
                Text(
                  'All temporary revenue and expense accounts will be zeroed out. '
                  'Net profit of ${AmountFormat.format(d.netProfit)} will be credited to Retained Earnings (EQT-RE).',
                  style: AppTextStyles.body,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.bgLight,
                    borderRadius: AppRadius.card,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(children: [
                          Icon(Icons.account_tree_outlined, color: AppColors.brandNavy),
                          SizedBox(height: 4),
                          Text('Revenue & Expense\n(Balances to zero)', textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                      Icon(Icons.arrow_forward_rounded, color: AppColors.goldAccent),
                      Expanded(
                        child: Column(children: [
                          Icon(Icons.shield_outlined, color: AppColors.success),
                          SizedBox(height: 4),
                          Text('Retained Earnings\n(EQT-RE updated)', textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmStep() {
    final d = _dashboard!;
    final fy = d.financialYear;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, color: AppColors.brandNavy, size: 28),
                    SizedBox(width: 12),
                    Text('Lock Confirmation', style: AppTextStyles.h1),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'This will permanently lock FY ${fy.name}. All periods up to ${DateFormat('dd-MMM-yyyy').format(fy.endDate)} will be sealed.',
                  style: AppTextStyles.body,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    border: Border.all(color: AppColors.warning),
                    borderRadius: AppRadius.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Text('Warning: Permanent Operation',
                            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.warning)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ensure all tax audits, returns, adjustments, depreciation, and reconciliations are finalized. '
                        'Once locked, modifications cannot be made to the books.',
                        style: TextStyle(fontSize: 12, color: AppColors.warning),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Type "CLOSE FY ${fy.name}" to confirm:', style: AppTextStyles.bodySmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmController,
                  decoration: InputDecoration(
                    hintText: 'CLOSE FY ${fy.name}',
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: _confirmEnabled ? AppColors.success : AppColors.borderInput,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessScreen() {
    final refNum = _closeResult?['reference_number'] ?? 'N/A';
    final newFY = _closeResult?['new_financial_year_name'] ?? 'N/A';

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(24.0),
        child: AppCard(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success, size: 64),
                const SizedBox(height: 24),
                Text('Financial Year Closed', style: AppTextStyles.display.copyWith(fontSize: 24)),
                const SizedBox(height: 12),
                Text(
                  'The financial year has been successfully finalized, closed, and locked.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 20),
                _buildResultRow('Closing Journal Entry:', refNum),
                const SizedBox(height: 8),
                _buildResultRow('Status:', 'LOCKED'),
                const SizedBox(height: 8),
                _buildResultRow('New Active FY:', newFY),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ActionButton(
                    label: 'Done',
                    icon: Icons.done,
                    tier: ActionTier.safe,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
        Text(value, style: TextStyle(fontFamily: 'monospace')),
      ],
    );
  }

  Widget _buildBottomNavigation() {
    final d = _dashboard;
    final canProceed = d?.closingAllowed ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            OutlinedButton.icon(
              onPressed: () => setState(() => _currentStep--),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back'),
            )
          else
            const SizedBox.shrink(),
          Row(
            children: [
              if (_currentStep == 0)
                OutlinedButton.icon(
                  onPressed: _loadDashboard,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Re-audit'),
                ),
              const SizedBox(width: 12),
              if (_currentStep < 2)
                ElevatedButton(
                  onPressed: canProceed ? () => setState(() => _currentStep++) : null,
                  child: Row(
                    children: [
                      Text('Next'),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _confirmEnabled ? _executeClosing : null,
                  icon: const Icon(Icons.lock_outlined, size: 16),
                  label: const Text('Confirm & Lock Year'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckItem {
  final String label;
  final bool passed;
  const _CheckItem(this.label, this.passed);
}
