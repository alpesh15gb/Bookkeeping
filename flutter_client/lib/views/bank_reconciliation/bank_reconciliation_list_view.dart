import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/bank_reconciliation_provider.dart';
import 'package:flutter_client/providers/banking_profile_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class BankReconciliationListView extends StatefulWidget {
  const BankReconciliationListView({super.key});

  @override
  State<BankReconciliationListView> createState() => _BankReconciliationListViewState();
}

class _BankReconciliationListViewState extends State<BankReconciliationListView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BankReconciliationProvider>().fetchStatements();
      context.read<BankingProfileProvider>().fetchBankingProfiles();
    });
  }

  void _showImportDialog() {
    final provider = context.read<BankingProfileProvider>();
    if (provider.profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a banking profile first in Banking screen'), backgroundColor: AppColors.warning),
      );
      return;
    }

    String? selectedProfileId;
    final dateCtrl = TextEditingController(
      text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Import Statement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedProfileId,
                decoration: const InputDecoration(labelText: 'Banking Profile *'),
                items: provider.profiles.map((p) => DropdownMenuItem<String>(
                  value: p['id'],
                  child: Text('${p['bank_name']} — ${p['account_number'] ?? ''}'),
                )).toList(),
                onChanged: (v) => setDialogState(() => selectedProfileId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: dateCtrl,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Statement Date'),
                onTap: () async {
                  final date = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
                  if (date != null) dateCtrl.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (selectedProfileId == null) return;
                Navigator.pop(ctx);
                final brProvider = context.read<BankReconciliationProvider>();
                final ok = await brProvider.uploadStatement({
                  'banking_profile_id': selectedProfileId,
                  'statement_date': dateCtrl.text,
                });
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(brProvider.errorMessage ?? 'Upload failed'), backgroundColor: AppColors.error),
                  );
                }
              },
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BankReconciliationProvider>();

    if (provider.isLoading) return const LoadingState(message: 'Loading bank statements...');
    if (provider.errorMessage != null) {
      return ErrorState(message: provider.errorMessage!, onRetry: () => provider.fetchStatements());
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showImportDialog(),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async => provider.fetchStatements(),
        child: provider.statements.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.account_balance_outlined,
                    title: 'No Bank Statements',
                    subtitle: 'Tap + to upload a bank statement and begin reconciliation',
                  ),
                ],
              )
            : ListView.builder(
                padding: AppSpacing.pagePadding,
                itemCount: provider.statements.length,
                itemBuilder: (context, i) {
                  final stmt = provider.statements[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: AppRadius.card,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.brandNavy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.account_balance_outlined, size: 18, color: AppColors.brandNavy),
                      ),
                      title: Text(stmt['bank_name'] ?? stmt['name'] ?? 'Statement ${i + 1}', style: AppTextStyles.h3),
                      subtitle: Text(stmt['account_number'] ?? '', style: AppTextStyles.caption),
                      trailing: Text('₹${(stmt['closing_balance'] ?? 0).toString()}', style: AppTextStyles.numeric),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
