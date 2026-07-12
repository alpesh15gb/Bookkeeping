/// Financial Year settings screen.
///
/// Lists all financial years for the company, allows creating a new one,
/// and switching the current active financial year.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/result/result.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/models/financial_year.dart';
import '../data/settings_repository.dart';
import 'settings_providers.dart';

class SettingsFinancialYearScreen extends ConsumerStatefulWidget {
  const SettingsFinancialYearScreen({super.key});

  @override
  ConsumerState<SettingsFinancialYearScreen> createState() =>
      _SettingsFinancialYearScreenState();
}

class _SettingsFinancialYearScreenState
    extends ConsumerState<SettingsFinancialYearScreen> {
  bool _isSwitching = false;

  String? get _companyId =>
      ref.read(authControllerProvider).activeMembership?.tenantId;

  Future<void> _setCurrent(FinancialYear fy) async {
    final companyId = _companyId;
    if (companyId == null || fy.isCurrent) return;

    setState(() => _isSwitching = true);
    final repo = ref.read(settingsRepositoryProvider);
    final result = await repo.setCurrentFinancialYear(companyId, fy.id);
    setState(() => _isSwitching = false);

    if (!mounted) return;
    if (result is Success<void>) {
      ref.invalidate(financialYearListProvider(companyId));
      ref.read(notificationServiceProvider).success(
        context,
        '${fy.name} is now the current financial year.',
        title: 'FY Changed',
      );
    } else {
      final err = (result as Failure<void>).error;
      ref.read(notificationServiceProvider).error(
        context,
        err.message,
        title: 'Switch failed',
      );
    }
  }

  Future<void> _showCreateDialog() async {
    final nameCtrl = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _CreateFinancialYearDialog(
        nameController: nameCtrl,
        onStartDateChanged: (d) => startDate = d,
        onEndDateChanged: (d) => endDate = d,
      ),
    );

    if (saved != true || startDate == null || endDate == null) {
      nameCtrl.dispose();
      return;
    }

    final companyId = _companyId;
    if (companyId == null) return;

    // Auto-generate name if empty.
    final name = nameCtrl.text.trim().isNotEmpty
        ? nameCtrl.text.trim()
        : 'FY ${startDate!.year}-${endDate!.year.toString().substring(2)}';

    final repo = ref.read(settingsRepositoryProvider);
    final result = await repo.createFinancialYear(
      companyId,
      name: name,
      startDate: startDate!,
      endDate: endDate!,
    );

    nameCtrl.dispose();
    if (!mounted) return;

    if (result is Success<FinancialYear>) {
      ref.invalidate(financialYearListProvider(companyId));
      ref.read(notificationServiceProvider).success(
        context,
        '${result.value.name} has been created.',
        title: 'FY Created',
      );
    } else {
      final err = (result as Failure<FinancialYear>).error;
      ref.read(notificationServiceProvider).error(
        context,
        err.message,
        title: 'Creation failed',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final companyId = _companyId;

    if (companyId == null) {
      return const Center(child: Text('No company selected.'));
    }

    final async = ref.watch(financialYearListProvider(companyId));

    return Scaffold(
      appBar: null,
      body: async.when(
        loading: () => const Center(child: LoadingSpinner(size: 36)),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () =>
              ref.invalidate(financialYearListProvider(companyId)),
        ),
        data: (fys) => _buildContent(colors, fys),
      ),
    );
  }

  Widget _buildContent(ApexColors colors, List<FinancialYear> fys) {
    return Column(
      children: [
        PageHeader(
          title: 'Financial Years',
          subtitle: 'Manage accounting periods',
          actions: [
            FilledButton.icon(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New FY'),
            ),
          ],
        ),
        Expanded(
          child: fys.isEmpty
              ? const EmptyState(
                  icon: Icons.calendar_month_outlined,
                  title: 'No financial years',
                  subtitle: 'Create your first financial year to start.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: fys.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _buildFYCard(colors, fys[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildFYCard(ApexColors colors, FinancialYear fy) {
    final isCurrent = fy.isCurrent;
    return ApexCard(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        onTap: isCurrent || _isSwitching ? null : () => _setCurrent(fy),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isCurrent
                    ? colors.primary.withValues(alpha: 0.1)
                    : colors.surfaceMuted,
                borderRadius: BorderRadius.circular(ApexRadius.md),
              ),
              child: Icon(
                isCurrent
                    ? Icons.check_circle_rounded
                    : Icons.calendar_month_outlined,
                size: 22,
                color: isCurrent ? colors.primary : colors.textSecondary,
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
                        fy.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(ApexRadius.pill),
                          ),
                          child: Text(
                            'CURRENT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatDate(fy.startDate)} — ${formatDate(fy.endDate)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (!isCurrent && !_isSwitching)
              TextButton(
                onPressed: () => _setCurrent(fy),
                child: const Text('Switch'),
              ),
            if (_isSwitching)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for creating a new financial year.
class _CreateFinancialYearDialog extends StatefulWidget {
  const _CreateFinancialYearDialog({
    required this.nameController,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
  });

  final TextEditingController nameController;
  final ValueChanged<DateTime> onStartDateChanged;
  final ValueChanged<DateTime> onEndDateChanged;

  @override
  State<_CreateFinancialYearDialog> createState() =>
      _CreateFinancialYearDialogState();
}

class _CreateFinancialYearDialogState
    extends State<_CreateFinancialYearDialog> {
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return AlertDialog(
      icon: Icon(
        Icons.calendar_month_outlined,
        size: 36,
        color: colors.primary,
      ),
      title: const Text('New Financial Year'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: widget.nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. FY 2026-27',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 16),
              // Start Date
              InkWell(
                onTap: () => _pickDate(
                  context,
                  initial: _startDate,
                  onPicked: (d) {
                    setState(() => _startDate = d);
                    widget.onStartDateChanged(d);
                  },
                ),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Start Date *',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    _startDate != null
                        ? formatDate(_startDate!)
                        : 'Select start date',
                    style: TextStyle(
                      color: _startDate != null
                          ? null
                          : colors.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // End Date
              InkWell(
                onTap: () => _pickDate(
                  context,
                  initial: _endDate,
                  onPicked: (d) {
                    setState(() => _endDate = d);
                    widget.onEndDateChanged(d);
                  },
                ),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'End Date *',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    _endDate != null
                        ? formatDate(_endDate!)
                        : 'Select end date',
                    style: TextStyle(
                      color: _endDate != null ? null : colors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_startDate == null || _endDate == null)
              ? null
              : () => Navigator.pop(context, true),
          child: const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _pickDate(
    BuildContext context, {
    DateTime? initial,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(picked);
  }
}
