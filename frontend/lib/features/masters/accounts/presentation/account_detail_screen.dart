/// Account detail screen — uses EntityDetailPage.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/entity_detail_page.dart';
import 'package:apexbooks/core/services/favorites_service.dart';
import 'package:apexbooks/core/services/recent_items_service.dart';
import '../data/models/account.dart';
import 'account_controller.dart';
import 'account_form_screen.dart';

class AccountDetailScreen extends ConsumerWidget {
  const AccountDetailScreen({
    super.key,
    required this.account,
    this.allAccounts = const [],
  });
  final Account account;

  /// Full account list, used to resolve the parent name and list children.
  final List<Account> allAccounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = apexColors(context);
    final fmt = ref.read(numberFormatterProvider);

    ref
        .read(recentItemsProvider.notifier)
        .add(
          RecentItem(
            id: account.id,
            title: account.name,
            category: 'accounts',
            route: '/masters/accounts/',
          ),
        );

    final favBtn = Consumer(
      builder: (context, ref, _) {
        final favs = ref.watch(favoritesProvider);
        final isFav = favs.any(
          (f) => f.id == account.id && f.category == 'accounts',
        );
        return IconButton(
          icon: Icon(isFav ? Icons.star_rounded : Icons.star_outline_rounded),
          onPressed: () => ref
              .read(favoritesProvider.notifier)
              .toggle(
                FavoriteItem(
                  id: account.id,
                  title: account.name,
                  category: 'accounts',
                  route: '/masters/accounts/',
                ),
              ),
        );
      },
    );

    final parent = account.parentId == null
        ? null
        : allAccounts.firstWhere(
            (a) => a.id == account.parentId,
            orElse: () => const Account(id: '', name: '—'),
          );
    final children = allAccounts
        .where((a) => a.parentId == account.id)
        .toList();

    final header = Row(
      children: [
        CircleAvatar(child: Icon(account.accountType.icon)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${account.code} · ${account.name}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                account.accountType.displayLabel,
                style: TextStyle(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );

    return EntityDetailPage(
      title: account.name,
      header: header,
      appBarActions: [favBtn],
      chips: [
        DetailChip(
          label: account.isActive ? 'Active' : 'Inactive',
          color: account.isActive ? colors.success : colors.danger,
        ),
        DetailChip(label: account.accountType.displayLabel, color: colors.info),
        if (account.isRoot) DetailChip(label: 'Root', color: colors.primary),
      ],
      sections: [
        DetailSection(
          title: 'Account Details',
          rows: [
            DetailRow('Code', account.code),
            DetailRow('Name', account.name),
            DetailRow('Type', account.accountType.displayLabel),
            DetailRow('Statement', account.accountType.statementGroup),
            DetailRow('Account Group', account.accountGroup ?? '—'),
            DetailRow(
              'Parent Account',
              account.isRoot ? '— None (root) —' : parent?.name ?? '—',
            ),
          ],
        ),
        DetailSection(
          title: 'Balances',
          rows: [
            DetailRow('Opening Balance', fmt.currency(account.openingBalance)),
            DetailRow('Current Balance', fmt.currency(account.currentBalance)),
            DetailRow(
              'Normal Balance',
              account.accountType.debitIncreases ? 'Debit' : 'Credit',
            ),
          ],
        ),
        if (children.isNotEmpty)
          DetailSection(
            title: 'Child Accounts (${children.length})',
            rows: children
                .map(
                  (c) => DetailRow(
                    '${c.code} · ${c.name}',
                    fmt.currency(c.currentBalance),
                  ),
                )
                .toList(),
          ),
      ],
      actions: [
        ActionItem(
          label: 'Edit',
          icon: Icons.edit_rounded,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    AccountFormScreen(account: account, existing: allAccounts),
              ),
            );
          },
        ),
        ActionItem(
          label: 'Delete',
          icon: Icons.delete_rounded,
          destructive: true,
          onTap: () async {
            final ok = await ref
                .read(accountControllerProvider.notifier)
                .delete(account, context);
            if (ok && context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
      timeline: [
        if (account.createdAt != null)
          TimelineEntry(
            title: 'Created',
            subtitle: 'Account was created',
            timestamp: account.createdAt!,
            icon: Icons.add_circle_outline,
            color: colors.success,
          ),
        if (account.updatedAt != null)
          TimelineEntry(
            title: 'Updated',
            subtitle: 'Account was last modified',
            timestamp: account.updatedAt!,
            icon: Icons.edit_outlined,
            color: colors.info,
          ),
      ],
    );
  }
}
