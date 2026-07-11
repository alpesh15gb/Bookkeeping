/// Banking Profile list screen — reuses BaseListScreen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/tables/table_column.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import '../data/models/banking_profile.dart';
import 'banking_profile_controller.dart';
import 'banking_profile_form_screen.dart';
import 'banking_profile_detail_screen.dart';

final bankingProfileTableControllerProvider =
    ChangeNotifierProvider.autoDispose<ApexTableController>((ref) {
      return ApexTableController();
    });

class BankingProfileListScreen extends ConsumerStatefulWidget {
  const BankingProfileListScreen({super.key});
  @override
  ConsumerState<BankingProfileListScreen> createState() =>
      _BankingProfileListScreenState();
}

class _BankingProfileListScreenState
    extends ConsumerState<BankingProfileListScreen> {
  late final ApexTableController _tableCtrl;

  @override
  void initState() {
    super.initState();
    _tableCtrl = ref.read(bankingProfileTableControllerProvider);
  }

  List<ApexColumn<BankingProfile>> _buildColumns() {
    final colors = apexColors(context);
    return [
      ApexColumn<BankingProfile>(
        id: 'bank_name',
        label: 'Bank',
        value: (b) => b.bankName,
        sortable: true,
        width: 180,
        cellBuilder: (ctx, b, _) => Row(
          children: [
            Icon(
              Icons.account_balance_outlined,
              size: 18,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                b.bankName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (b.isPrimary)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: colors.warning,
                ),
              ),
          ],
        ),
      ),
      ApexColumn<BankingProfile>(
        id: 'account_holder',
        label: 'Account Holder',
        value: (b) => b.accountHolderName,
        sortable: true,
        width: 160,
      ),
      ApexColumn<BankingProfile>(
        id: 'account_number',
        label: 'A/C No.',
        value: (b) => b.maskedNumber,
        width: 130,
      ),
      ApexColumn<BankingProfile>(
        id: 'ifsc',
        label: 'IFSC',
        value: (b) => b.ifscCode,
        width: 120,
        cellBuilder: (ctx, b, _) => Text(
          b.ifscCode,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
      ApexColumn<BankingProfile>(
        id: 'branch',
        label: 'Branch',
        value: (b) => b.branchName ?? '\u2014',
        width: 140,
      ),
      ApexColumn<BankingProfile>(
        id: 'status',
        label: 'Status',
        value: (b) => b.isActive ? 'Active' : 'Inactive',
        sortable: true,
        width: 90,
        cellBuilder: (ctx, b, _) => Align(
          alignment: Alignment.centerLeft,
          child: StatusBadge(
            label: b.isActive ? 'ACTIVE' : 'INACTIVE',
            tone: b.isActive ? StatusTone.success : StatusTone.neutral,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return BaseListScreen<BankingProfile>(
      title: 'Banking Profiles',
      columns: _buildColumns(),
      provider: bankingProfileControllerProvider,
      tableCtrl: _tableCtrl,
      searchHint: 'Search by bank name, holder or IFSC',
      emptyTitle: 'No banking profiles yet',
      emptySubtitle: 'Add your first bank or payment account.',
      onCreate: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BankingProfileFormScreen()),
      ),
      onRowTap: (b) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BankingProfileDetailScreen(profile: b),
        ),
      ),
    );
  }
}
