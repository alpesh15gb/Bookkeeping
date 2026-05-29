import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/accounting/account_form_view.dart';

class AccountDetailView extends StatefulWidget {
  final String accountId;

  const AccountDetailView({super.key, required this.accountId});

  @override
  State<AccountDetailView> createState() => _AccountDetailViewState();
}

class _AccountDetailViewState extends State<AccountDetailView> {
  Map<String, dynamic>? _account;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final provider = context.read<AccountingProvider>();
    final data = await provider.fetchAccountDetail(widget.accountId);
    if (mounted) {
      setState(() {
        _account = data;
        _loading = false;
      });
    }
  }

  void _showEditForm() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        child: AccountFormView(
          editAccount: _account,
          onSuccess: () {
            Navigator.of(ctx).pop();
            _load();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingState(message: 'Loading account...'));
    if (_account == null) {
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        body: const ErrorState(message: 'Account not found'),
      );
    }

    final isMobile = AdaptiveLayout.isMobile(context);
    final a = _account!;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        elevation: 0.5,
        title: Text(a['name'] ?? 'Account', style: AppTextStyles.h3),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _showEditForm,
          ),
        ],
      ),
      body: ListView(
        padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Balance', style: AppTextStyles.h3),
                    Text(
                      '₹${double.parse((a['balance'] ?? 0).toString()).toStringAsFixed(2)}',
                      style: AppTextStyles.numericLarge,
                    ),
                  ],
                ),
                const Divider(height: 24),
                _detailRow('Type', a['account_type'] ?? '-'),
                _detailRow('Code', a['code'] ?? '-'),
                _detailRow('Group', a['group_name'] ?? a['group'] ?? '-'),
              ],
            ),
          ),
          if (a['description'] != null) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Description', style: AppTextStyles.h3),
                  const SizedBox(height: 6),
                  Text(a['description'], style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.caption),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
