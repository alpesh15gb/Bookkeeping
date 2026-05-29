import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/banking_profile_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
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
            ? ListView(children: const [SizedBox(height: 120), EmptyState(icon: Icons.account_balance, title: 'No Banking Profiles', subtitle: 'Add a bank account for payments and GST invoices')])
            : ListView.builder(
                padding: AppSpacing.pagePadding,
                itemCount: profiles.length,
                itemBuilder: (context, i) {
                  final p = profiles[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: AppColors.bgSurface, borderRadius: AppRadius.card, border: Border.all(color: AppColors.border)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: AppColors.brandNavy.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.account_balance, size: 18, color: AppColors.brandNavy),
                      ),
                      title: Text(p['bank_name'] ?? 'N/A', style: AppTextStyles.h3),
                      subtitle: Text(p['account_number'] ?? '', style: AppTextStyles.caption),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (p['is_primary'] == true) ...[
                            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.successBg, borderRadius: AppRadius.badge), child: const Text('Primary', style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w600))),
                            const SizedBox(width: 8),
                          ],
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
