import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
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
  DateTime _closingDate = DateTime.now();
  bool _isInitialized = false;
  Map<String, dynamic>? _prepData;
  Map<String, dynamic>? _closeResult;
  String? _localError;
  bool _isPerformingAction = false;

  @override
  void initState() {
    super.initState();
    // Default closing date: March 31 of current or next year based on current date
    final now = DateTime.now();
    DateTime defaultClose = DateTime(now.year, 3, 31);
    if (defaultClose.isBefore(now)) {
      defaultClose = DateTime(now.year + 1, 3, 31);
    }
    _closingDate = defaultClose;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _loadPrepareData();
      _isInitialized = true;
    }
  }

  Future<void> _loadPrepareData() async {
    setState(() {
      _localError = null;
      _prepData = null;
    });

    final provider = context.read<AccountingProvider>();
    final formattedDate = DateFormat('yyyy-MM-dd').format(_closingDate);
    final data = await provider.fetchYearEndPrepare(formattedDate);

    if (data == null && provider.errorMessage != null) {
      setState(() {
        _localError = provider.errorMessage;
      });
    } else if (data != null) {
      setState(() {
        _prepData = data;
        // If the backend has a different financial year start, we can verify or adjust if needed.
      });
    }
  }

  Future<void> _executeClosing() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('Confirm Year End Close'),
          ],
        ),
        content: Text(
          'Are you absolutely sure you want to close the financial year ending on ${DateFormat('dd-MMM-yyyy').format(_closingDate)}?\n\n'
          'This action will:\n'
          '1. Post a closing journal entry transferring Net Profit/Loss to Retained Earnings.\n'
          '2. Lock all accounting periods up to this date permanently.\n'
          '3. Update the company\'s financial year start to the next day.\n\n'
          'This action is irreversible.',
          style: AppTextStyles.body,
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Close Year'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isPerformingAction = true;
      _localError = null;
    });

    final provider = context.read<AccountingProvider>();
    final formattedDate = DateFormat('yyyy-MM-dd').format(_closingDate);
    final result = await provider.closeYearEnd(formattedDate);

    setState(() {
      _isPerformingAction = false;
    });

    if (result == null && provider.errorMessage != null) {
      setState(() {
        _localError = provider.errorMessage;
      });
    } else if (result != null) {
      setState(() {
        _closeResult = result;
        _currentStep = 3; // Success state page
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _closingDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.brandNavy,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _closingDate) {
      setState(() {
        _closingDate = picked;
        _currentStep = 0; // Reset step back to beginning when date changes
      });
      _loadPrepareData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final provider = context.watch<AccountingProvider>();

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
                child: Text(
                  'Year End Closing & Lock',
                  style: AppTextStyles.h2,
                ),
              ),
              if (_currentStep < 3)
                TextButton.icon(
                  onPressed: _selectDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(
                    'Closing Date: ${DateFormat('dd-MMM-yyyy').format(_closingDate)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: _isPerformingAction
          ? const LoadingState(message: 'Executing Year End Closing operations...')
          : _buildMainContent(provider, isMobile),
    );
  }

  Widget _buildMainContent(AccountingProvider provider, bool isMobile) {
    if (_localError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: AppCard(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                  const SizedBox(height: 16),
                  Text('Pre-closure Check Failed', style: AppTextStyles.h2),
                  const SizedBox(height: 8),
                  Text(
                    _localError!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: _selectDate,
                        child: const Text('Change Closing Date'),
                      ),
                      const SizedBox(width: 12),
                      ActionButton(
                        label: 'Retry Check',
                        icon: Icons.refresh,
                        onPressed: _loadPrepareData,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_prepData == null) {
      return const LoadingState(message: 'Running pre-close audit verification...');
    }

    if (_currentStep == 3) {
      return _buildSuccessScreen();
    }

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

  Widget _buildStepIndicator() {
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildStepIndicatorNode(0, '1. Pre-close Audit'),
          _buildStepIndicatorLine(0),
          _buildStepIndicatorNode(1, '2. Net profit / Retained Earnings'),
          _buildStepIndicatorLine(1),
          _buildStepIndicatorNode(2, '3. Lock & Finalize'),
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone
                ? AppColors.success
                : (isActive ? AppColors.brandNavy : AppColors.bgLight),
            border: Border.all(
              color: isActive ? AppColors.brandNavy : AppColors.border,
            ),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: isActive ? Colors.white : AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: isActive ? AppColors.brandNavy : AppColors.textSecondary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildStepIndicatorLine(int fromIndex) {
    final isDone = _currentStep > fromIndex;
    return Container(
      width: 40,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: isDone ? AppColors.success : AppColors.border,
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildAuditStep();
      case 1:
        return _buildPNLStep();
      case 2:
        return _buildLockStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAuditStep() {
    final ready = _prepData?['ready'] ?? false;
    final tbBalanced = _prepData?['trial_balance_balanced'] ?? false;
    final tbDiff = _prepData?['trial_balance_difference'] ?? 0.0;
    final unpostedCount = _prepData?['unposted_documents_count'] ?? 0;
    final unpostedDocs = _prepData?['unposted_documents'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top summary banner
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Icon(
                  ready ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  color: ready ? AppColors.success : AppColors.warning,
                  size: 40,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ready
                            ? 'Books are fully audited and ready to close'
                            : 'Unresolved issues blocking closure',
                        style: AppTextStyles.h2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ready
                            ? 'Trial Balance is balanced and no draft documents exist for this period.'
                            : 'Please review and fix the warnings below before finalizing.',
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

        // Trial Balance Check Card
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      tbBalanced ? Icons.check_circle_outline : Icons.error_outline,
                      color: tbBalanced ? AppColors.success : AppColors.error,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text('Trial Balance Status', style: AppTextStyles.h2),
                    const Spacer(),
                    StatusBadge(
                      label: tbBalanced ? 'Balanced' : 'Out of Balance',
                      backgroundColor: tbBalanced ? AppColors.successBg : AppColors.errorBg,
                      color: tbBalanced ? AppColors.success : AppColors.error,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  tbBalanced
                      ? 'The total debits match the total credits. Your ledger balances are clean.'
                      : 'The trial balance does not balance. Closing now would result in an unbalanced ledger state.',
                  style: AppTextStyles.bodySmall,
                ),
                if (!tbBalanced) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: AppRadius.card,
                    ),
                    child: Row(
                      children: [
                        const Text('Difference Amount:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                        const Spacer(),
                        Text(
                          AmountFormat.format(tbDiff),
                          style: AppTextStyles.numeric.copyWith(color: AppColors.error, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Unposted Documents Check Card
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      unpostedCount == 0 ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                      color: unpostedCount == 0 ? AppColors.success : AppColors.warning,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text('Draft / Unposted Documents', style: AppTextStyles.h2),
                    const Spacer(),
                    StatusBadge(
                      label: unpostedCount == 0 ? 'All Posted' : '$unpostedCount Pending',
                      backgroundColor: unpostedCount == 0 ? AppColors.successBg : AppColors.warningBg,
                      color: unpostedCount == 0 ? AppColors.success : AppColors.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  unpostedCount == 0
                      ? 'No draft invoices, bills, expenses, or returns found. All entries have been locked or posted.'
                      : 'You have draft documents in this period. Drafts must be posted to the ledger or deleted before closing the year.',
                  style: AppTextStyles.bodySmall,
                ),
                if (unpostedDocs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Unposted Documents List:', style: AppTextStyles.h3),
                  const SizedBox(height: 8),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: unpostedDocs.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, idx) {
                      final doc = unpostedDocs[idx];
                      final dateStr = doc['date'] != null
                          ? DateFormat('dd-MMM-yyyy').format(DateTime.parse(doc['date']))
                          : '';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${doc['document_type'] ?? 'DOC'} #${doc['document_number'] ?? ''}',
                                  style: AppTextStyles.bodyMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(dateStr, style: AppTextStyles.caption),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              AmountFormat.format(doc['amount'] ?? 0.0),
                              style: AppTextStyles.numeric,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPNLStep() {
    final netProfit = _prepData?['net_profit'] ?? 0.0;
    final isLoss = netProfit < 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Icon(
                  isLoss ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                  color: isLoss ? AppColors.warning : AppColors.success,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  isLoss ? 'Net Financial Loss for the Year' : 'Net Financial Profit for the Year',
                  style: AppTextStyles.h2,
                ),
                const SizedBox(height: 8),
                Text(
                  AmountFormat.format(netProfit),
                  style: AppTextStyles.amountLarge.copyWith(
                    color: isLoss ? AppColors.warning : AppColors.success,
                    fontSize: 32,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Calculated from the beginning of this financial year (${DateFormat('dd-MMM-yyyy').format(DateTime.parse(_prepData?['financial_year_start'] ?? _closingDate.toString()))}) '
                  'to the closing date (${DateFormat('dd-MMM-yyyy').format(_closingDate)}).',
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
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Retained Earnings Account Posting', style: AppTextStyles.h2),
                const SizedBox(height: 12),
                Text(
                  'During closing, all temporary revenue and expense accounts will be zeroed out. '
                  'The net profit of ${AmountFormat.format(netProfit)} will be credited to your Retained Earnings account (EQT-RE). '
                  'This rolls your earnings forward into the equity balance sheet for the next financial year.',
                  style: AppTextStyles.body,
                ),
                const SizedBox(height: 20),
                // visual schema/flowchart
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
                        child: Column(
                          children: const [
                            Icon(Icons.account_tree_outlined, color: AppColors.brandNavy),
                            SizedBox(height: 4),
                            Text('Revenue & Expense\n(Balances to zero)', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded, color: AppColors.goldAccent),
                      Expanded(
                        child: Column(
                          children: const [
                            Icon(Icons.shield_outlined, color: AppColors.success),
                            SizedBox(height: 4),
                            Text('Retained Earnings\n(EQT-RE updated)', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
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

  Widget _buildLockStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.lock_outline_rounded, color: AppColors.brandNavy, size: 28),
                    SizedBox(width: 12),
                    Text('Locking Accounting Period', style: AppTextStyles.h1),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Finalizing the year will automatically lock the accounting periods. '
                  'This prevents any future manual entries, changes, or deletions of invoices, bills, expenses, '
                  'or ledger details prior to and including the closing date (${DateFormat('dd-MMM-yyyy').format(_closingDate)}).',
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Warning: Permanent Operation',
                              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.warning),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Ensure you have finalized all tax audits, returns, adjustments, depreciation, and reconciliations before initiating this step. Once locked, modifications cannot be made to the books.',
                              style: TextStyle(fontSize: 12, color: AppColors.warning),
                            ),
                          ],
                        ),
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

  Widget _buildSuccessScreen() {
    final journal = _closeResult;
    final entryNumber = journal?['entry_number'] ?? 'N/A';

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
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 64,
                ),
                const SizedBox(height: 24),
                Text(
                  'Financial Year Closed',
                  style: AppTextStyles.display.copyWith(fontSize: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  'The financial year ending on ${DateFormat('dd-MMM-yyyy').format(_closingDate)} has been successfully finalized, closed, and locked.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Closing Journal Entry:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(entryNumber, style: const TextStyle(fontFamily: 'monospace')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Status:', style: TextStyle(fontWeight: FontWeight.bold)),
                    StatusBadge(
                      label: 'LOCKED',
                      backgroundColor: AppColors.brandNavy.withOpacity(0.1),
                      color: AppColors.brandNavy,
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ActionButton(
                    label: 'Done',
                    icon: Icons.done,
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    final ready = _prepData?['ready'] ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
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
                  onPressed: _loadPrepareData,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Re-audit'),
                ),
              const SizedBox(width: 12),
              if (_currentStep < 2)
                ElevatedButton(
                  onPressed: ready
                      ? () => setState(() => _currentStep++)
                      : null,
                  child: Row(
                    children: const [
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
                  onPressed: ready ? _executeClosing : null,
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
