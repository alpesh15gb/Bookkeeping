import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/shared/design_system.dart' as ds;
import 'package:flutter_client/views/expenses/expense_form_view.dart';

class ExpenseDetailView extends StatefulWidget {
  final String expenseId;

  const ExpenseDetailView({super.key, required this.expenseId});

  @override
  State<ExpenseDetailView> createState() => _ExpenseDetailViewState();
}

class _ExpenseDetailViewState extends State<ExpenseDetailView> {
  Map<String, dynamic>? _expense;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  void _fetchDetail() async {
    final detail = await context.read<DocumentProvider>().fetchExpenseDetail(widget.expenseId);
    if (mounted) {
      setState(() {
        _expense = detail;
        _isLoading = false;
      });
    }
  }

  void _deleteExpense() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Delete Expense?',
      message: 'Are you sure you want to delete this expense? This cannot be undone.',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<DocumentProvider>();
      final success = await provider.deleteExpense(widget.expenseId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          Navigator.pop(context, true);
        } else {
          AppToast.error(context, provider.errorMessage ?? 'Delete failed');
        }
      }
    }
  }

  void _postExpense() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Post to Ledger?',
      message: 'This will create a journal entry and post the expense to the ledger. Continue?',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<DocumentProvider>();
      final success = await provider.postExpense(widget.expenseId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _fetchDetail();
        } else {
          AppToast.error(context, provider.errorMessage ?? 'Post failed');
        }
      }
    }
  }

  void _cancelExpense() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel Expense?',
      message: 'This will create a reversal journal entry. Continue?',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<DocumentProvider>();
      final success = await provider.cancelExpense(widget.expenseId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          Navigator.pop(context, true);
        } else {
          AppToast.error(context, provider.errorMessage ?? 'Cancel failed');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: LoadingState(message: 'Loading expense details...'));
    if (_expense == null) return const Scaffold(body: ErrorState(message: 'Expense not found.'));

    final isMobile = AdaptiveLayout.isMobile(context);
    final status = _expense!['status'] ?? 'POSTED';
    final amount = double.tryParse((_expense!['amount'] ?? 0).toString()) ?? 0.0;
    final total = double.tryParse((_expense!['total'] ?? 0).toString()) ?? 0.0;
    final cgst = double.tryParse((_expense!['cgst_amount'] ?? 0).toString()) ?? 0.0;
    final sgst = double.tryParse((_expense!['sgst_amount'] ?? 0).toString()) ?? 0.0;
    final igst = double.tryParse((_expense!['igst_amount'] ?? 0).toString()) ?? 0.0;
    final cess = double.tryParse((_expense!['cess_amount'] ?? 0).toString()) ?? 0.0;
    final roundOff = double.tryParse((_expense!['round_off'] ?? 0).toString()) ?? 0.0;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(_expense!['expense_number'] ?? 'Expense Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExpenseFormView(editExpense: _expense),
                ),
              ).then((updated) {
                if (updated == true) _fetchDetail();
              });
            },
            tooltip: 'Edit expense',
          ),
          const SizedBox(width: 8),
          StatusBadge(label: status),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Card
            ds.AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE57C00).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: const Icon(
                          Icons.money_off_rounded,
                          size: 20,
                          color: Color(0xFFE57C00),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('EXPENSE RECORD', style: AppTextStyles.labelSmall),
                            Text(
                              _expense!['expense_number'] ?? 'EXPENSE',
                              style: AppTextStyles.h2,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  ds.AppInfoRow(label: 'Category', value: _expense!['category_name'] ?? 'N/A'),
                  ds.AppInfoRow(label: 'Expense Date', value: ds.AppDate.format(_expense!['expense_date'])),
                  ds.AppInfoRow(label: 'Vendor', value: _expense!['vendor_name'] ?? 'N/A'),
                  ds.AppInfoRow(label: 'Description', value: _expense!['description'] ?? 'N/A'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tax Summary Card
            ds.AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ds.AppSection(
                    title: 'Amount & Tax Summary',
                    child: Column(
                      children: [
                        ds.AppInfoRow(label: 'Subtotal', value: AmountFormat.format(amount)),
                        ds.AppInfoRow(label: 'CGST', value: AmountFormat.format(cgst)),
                        ds.AppInfoRow(label: 'SGST', value: AmountFormat.format(sgst)),
                        ds.AppInfoRow(label: 'IGST', value: AmountFormat.format(igst)),
                        if (cess > 0) ds.AppInfoRow(label: 'Cess', value: AmountFormat.format(cess)),
                        ds.AppInfoRow(label: 'Round Off', value: AmountFormat.format(roundOff)),
                        const Divider(),
                        ds.AppInfoRow(
                          label: 'Total Paid',
                          value: AmountFormat.format(total),
                          isBold: true,
                          valueColor: AppColors.brandNavy,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Cancel / Delete Button based on status
            if (status == 'POSTED')
              ds.AppButton(
                label: 'Cancel Expense (Reverse Journal)',
                icon: Icons.undo,
                color: AppColors.error,
                textColor: AppColors.textWhite,
                onTap: _cancelExpense,
              ),
            if (status == 'DRAFT') ...[
              ds.AppButton(
                label: 'Post to Ledger',
                icon: Icons.book_rounded,
                isPrimary: true,
                onTap: _postExpense,
              ),
              const SizedBox(height: 12),
              ds.AppButton(
                label: 'Delete Expense Record',
                icon: Icons.delete_outline,
                color: AppColors.error,
                textColor: AppColors.textWhite,
                onTap: _deleteExpense,
              ),
            ],
            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }
}
