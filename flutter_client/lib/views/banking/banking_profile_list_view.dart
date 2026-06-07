import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/banking_profile_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart' show LoadingState;
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/banking/banking_profile_form_view.dart';

class BankingProfileListView extends StatefulWidget {
  const BankingProfileListView({super.key});

  @override
  State<BankingProfileListView> createState() => _BankingProfileListViewState();
}

class _BankingProfileListViewState extends State<BankingProfileListView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BankingProfileProvider>().fetchBankingProfiles();
    });
  }

  String _formatAccountNumber(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    if (raw.length <= 4) return raw;
    return '•••• •••• •••• ${raw.substring(raw.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BankingProfileProvider>();
    final profiles = provider.profiles;
    final isMobile = AdaptiveLayout.isMobile(context);

    if (provider.isLoading && profiles.isEmpty) {
      return const LoadingState(message: 'Loading profiles...');
    }

    Widget listContent;
    if (profiles.isEmpty) {
      listContent = ListView(
        children: const [
          SizedBox(height: 120),
          AppEmptyState(
            icon: Icons.account_balance,
            title: 'No Bank Accounts',
            subtitle: 'Add a bank account for payment records, tracking, and GST printouts',
          )
        ],
      );
    } else {
      listContent = ListView.builder(
        padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
        itemCount: profiles.length,
        itemBuilder: (context, i) {
          final p = profiles[i];
          final isPrimary = p['is_primary'] == true;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isPrimary
                    ? [AppColors.brandNavy, AppColors.brandNavy.withOpacity(0.85)]
                    : [AppColors.bgSurface, AppColors.bgSurface],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPrimary ? AppColors.goldAccent : AppColors.border,
                width: isPrimary ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isPrimary
                                  ? AppColors.goldAccent.withOpacity(0.15)
                                  : AppColors.brandNavy.withOpacity(0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.account_balance_rounded,
                              color: isPrimary ? AppColors.goldAccent : AppColors.brandNavy,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p['bank_name'] ?? 'N/A',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isPrimary ? AppColors.textWhite : AppColors.textPrimary,
                                ),
                              ),
                              if (p['branch_name'] != null && p['branch_name'].toString().isNotEmpty)
                                Text(
                                  p['branch_name'],
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isPrimary ? AppColors.textWhite.withOpacity(0.7) : AppColors.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          if (isPrimary)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.goldAccent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'PRIMARY',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppColors.brandNavy,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: isPrimary ? AppColors.goldAccent : AppColors.textMuted,
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BankingProfileFormView(profile: p),
                              ),
                            ).then((_) => provider.fetchBankingProfiles()),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _formatAccountNumber(p['account_number']),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Courier',
                      letterSpacing: 1.5,
                      color: isPrimary ? AppColors.textWhite : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'IFSC CODE',
                            style: TextStyle(
                              fontSize: 9,
                              color: isPrimary ? AppColors.textWhite.withOpacity(0.6) : AppColors.textMuted,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p['ifsc_code'] ?? 'N/A',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isPrimary ? AppColors.textWhite : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      if (p['is_active'] == false)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Inactive',
                            style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('Bank Accounts', style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => provider.fetchBankingProfiles(),
              child: listContent,
            ),
          ),
          // Sticky Bottom Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              border: const Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Add Bank Account',
                      icon: Icons.add_rounded,
                      isPrimary: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BankingProfileFormView()),
                      ).then((_) => provider.fetchBankingProfiles()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
