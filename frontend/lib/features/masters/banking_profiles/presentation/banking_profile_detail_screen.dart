/// Banking Profile detail screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/entity_detail_page.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/result/result.dart';
import '../data/models/banking_profile.dart';
import 'banking_profile_controller.dart';
import 'banking_profile_form_screen.dart';

class BankingProfileDetailScreen extends ConsumerWidget {
  const BankingProfileDetailScreen({super.key, required this.profile});
  final BankingProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = (String? v) => v ?? '\u2014';

    return EntityDetailPage(
      title: profile.bankName,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profile.bankName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            profile.shortLabel,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
      chips: [
        DetailChip(
          label: profile.isPrimary ? 'Primary' : 'Not Primary',
          color: profile.isPrimary ? apexColors(context).accent : apexColors(context).textMuted,
        ),
        DetailChip(
          label: profile.isActive ? 'Active' : 'Inactive',
          color: profile.isActive ? apexColors(context).success : apexColors(context).danger,
        ),
      ],
      sections: [
        DetailSection(
          title: 'Account Information',
          rows: [
            DetailRow('Account Holder', profile.accountHolderName),
            DetailRow('Account Number', profile.maskedNumber),
            DetailRow('IFSC Code', profile.ifscCode),
            DetailRow('Branch', fmt(profile.branchName)),
          ],
        ),
        DetailSection(
          title: 'Banking',
          rows: [DetailRow('UPI ID', fmt(profile.upiId))],
        ),
      ],
      actions: [
        ActionItem(
          icon: Icons.edit_rounded,
          label: 'Edit',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BankingProfileFormScreen(profile: profile),
              ),
            );
          },
        ),
        ActionItem(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          onTap: () => _delete(context, ref),
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete banking profile "${profile.bankName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final notif = ref.read(notificationServiceProvider);
    final repo = ref.read(bankingProfileRepositoryProvider);
    final result = await repo.delete(profile.id);
    if (!context.mounted) return;
    if (result is Success) {
      notif.success(context, 'Banking profile deleted.');
      ref.read(cacheServiceProvider).invalidatePrefix('banking-profiles:');
      Navigator.of(context).pop();
    } else {
      notif.error(context, 'Failed to delete.');
    }
  }
}
