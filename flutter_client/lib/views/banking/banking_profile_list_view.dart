import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/banking_profile_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/shared/document_list_view.dart';
import 'package:flutter_client/views/banking/banking_profile_form_view.dart';

class BankingProfileListView extends StatefulWidget {
  const BankingProfileListView({super.key});

  @override
  State<BankingProfileListView> createState() => _BankingProfileListViewState();
}

class _BankingProfileListViewState extends State<BankingProfileListView> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BankingProfileProvider>().fetchBankingProfiles();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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

    final items = profiles.where((p) {
      final query = _searchCtrl.text.trim().toLowerCase();
      if (query.isEmpty) return true;
      final bank = (p['bank_name'] ?? '').toString().toLowerCase();
      final branch = (p['branch_name'] ?? '').toString().toLowerCase();
      final account = (p['account_number'] ?? '').toString().toLowerCase();
      return bank.contains(query) || branch.contains(query) || account.contains(query);
    }).map((p) {
      return DocumentItemData(
        id: p['id'].toString(),
        docNumber: p['bank_name'] ?? 'Bank',
        partyName: p['branch_name'] ?? '',
        amount: 0,
        status: p['is_primary'] == true ? 'PRIMARY' : (p['is_active'] == false ? 'INACTIVE' : 'ACTIVE'),
      );
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BankingProfileFormView()),
        ).then((_) => provider.fetchBankingProfiles()),
        child: const Icon(Icons.add),
      ),
      body: DocumentListView(
        title: 'Bank Accounts',
        searchController: _searchCtrl,
        searchHint: 'Search bank accounts...',
        onSearchChanged: (_) => setState(() {}),
        filterTabs: const [],
        activeFilter: '',
        onFilterChanged: (_) {},
        items: items,
        isLoading: provider.isLoading && profiles.isEmpty,
        onRefresh: () async => provider.fetchBankingProfiles(),
        emptyTitle: 'No Bank Accounts',
        emptySubtitle: 'Add a bank account for payment records, tracking, and GST printouts',
        emptyIcon: Icons.account_balance,
        detailBuilder: (ctx, item) {
          final profile = profiles.firstWhere((p) => p['id'].toString() == item.id, orElse: () => {});
          return BankingProfileFormView(profile: profile);
        },
        itemBuilder: (context, item, index) {
          final p = profiles.firstWhere((pw) => pw['id'].toString() == item.id, orElse: () => {});
          final isPrimary = p['is_primary'] == true;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isPrimary
                    ? [AppColors.brandNavy, AppColors.brandNavy.withValues(alpha: 0.85)]
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
                  color: Colors.black.withValues(alpha: 0.03),
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
                                  ? AppColors.goldAccent.withValues(alpha: 0.15)
                                  : AppColors.brandNavy.withValues(alpha: 0.05),
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
                                    color: isPrimary ? AppColors.textWhite.withValues(alpha: 0.7) : AppColors.textMuted,
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
                              child: Text(
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
                              color: isPrimary ? AppColors.textWhite.withValues(alpha: 0.6) : AppColors.textMuted,
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
                            color: AppColors.error.withValues(alpha: 0.1),
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
      ),
    );
  }
}
