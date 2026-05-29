import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/accounting/account_form_view.dart';

class AccountListView extends StatefulWidget {
  const AccountListView({super.key});

  @override
  State<AccountListView> createState() => _AccountListViewState();
}

class _AccountListViewState extends State<AccountListView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AccountingProvider>().fetchAccounts();
    });
  }

  void _showForm() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        child: AccountFormView(
          onSuccess: () {
            Navigator.of(ctx).pop();
            context.read<AccountingProvider>().fetchAccounts();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AccountingProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: AppColors.bgSurface,
          child: Row(
            children: [
              Expanded(child: Center(child: Text('Chart of Accounts', style: AppTextStyles.h3))),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ActionButton(
                  label: 'New',
                  icon: Icons.add,
                  tier: ActionTier.safe,
                  onPressed: _showForm,
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildBody(provider, isMobile),
    );
  }

  Widget _buildBody(AccountingProvider provider, bool isMobile) {
    if (provider.isLoading) return const LoadingState(message: 'Loading accounts...');
    if (provider.errorMessage != null) {
      return ErrorState(message: provider.errorMessage!, onRetry: () => provider.fetchAccounts());
    }

    final accounts = _buildAccountList(provider);

    if (accounts.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance_outlined,
        title: 'No accounts yet',
        subtitle: 'Chart of accounts will appear here',
      );
    }

    return ListView.separated(
      padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
      itemCount: accounts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final a = accounts[i];
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(a['name'] ?? 'Account', style: AppTextStyles.h3)),
                  if (a['account_type'] != null)
                    StatusBadge(label: a['account_type'], backgroundColor: AppColors.borderLight, color: AppColors.textSecondary),
                ],
              ),
              if (a['code'] != null) ...[
                const SizedBox(height: 4),
                Text('Code: ${a['code']}', style: AppTextStyles.caption),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Balance: ₹${double.parse((a['current_balance'] ?? 0).toString()).toStringAsFixed(2)}',
                    style: AppTextStyles.numeric,
                  ),
                  Text(
                    a['group_name'] ?? a['group'] ?? '',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<dynamic> _buildAccountList(AccountingProvider provider) {
    if (provider.accountsList != null) return provider.accountsList!;
    return [];
  }
}
