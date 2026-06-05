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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BankingProfileProvider>();
    final profiles = provider.profiles;

    if (provider.isLoading && profiles.isEmpty) return const LoadingState(message: 'Loading profiles...');

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BankingProfileFormView())).then((_) => provider.fetchBankingProfiles()),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async => provider.fetchBankingProfiles(),
        child: profiles.isEmpty
            ? ListView(children: const [SizedBox(height: 120), AppEmptyState(icon: Icons.account_balance, title: 'No Banking Profiles', subtitle: 'Add a bank account for payments and GST invoices')])
            : ListView.builder(
                padding: AppSpacing.pagePadding,
                itemCount: profiles.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: HeroSummaryCard(
                        title: 'Banking Profiles',
                        amount: profiles.length,
                        subtitle: '${profiles.where((p) => p['is_primary'] == true).length} primary',
                        icon: Icons.account_balance,
                      ),
                    );
                  }
                  final p = profiles[i - 1];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: AppListTile(
                        leadingText: (p['bank_name'] ?? 'B')[0].toString().toUpperCase(),
                        title: p['bank_name'] ?? 'N/A',
                        subtitle: p['account_number'] ?? '',
                        badge: p['is_primary'] == true
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.successBg, borderRadius: AppRadius.badge),
                              child: const Text('Primary', style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w600)),
                            )
                          : null,
                        hoverActions: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BankingProfileFormView(profile: p))).then((_) => provider.fetchBankingProfiles()),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
