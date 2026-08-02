/// Company selection screen.
///
/// Shown after authentication when the user belongs to more than one tenant,
/// or whenever they need to (re)select their active company. Selecting a
/// company calls [AuthController.selectTenant] and routes into the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/index.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/states.dart';
import '../data/models/membership_models.dart';
import 'auth_controller.dart';
import 'auth_routes.dart' as auth_routes;

class CompanySelectionScreen extends ConsumerStatefulWidget {
  const CompanySelectionScreen({super.key});
  @override
  ConsumerState<CompanySelectionScreen> createState() =>
      _CompanySelectionScreenState();
}

class _CompanySelectionScreenState
    extends ConsumerState<CompanySelectionScreen> {
  @override
  void initState() {
    super.initState();
    // Ensure memberships are fresh on entry.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier);
    });
  }

  Future<void> _select(Membership membership) async {
    await ref.read(authControllerProvider.notifier).selectTenant(membership);
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final auth = ref.watch(authControllerProvider);
    final memberships = auth.memberships;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select company'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOut();
              if (!context.mounted) return;
              context.go(auth_routes.login);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: memberships.isEmpty
            ? const EmptyState(
                icon: Icons.business_outlined,
                title: 'No companies yet',
                subtitle:
                    'You don\'t belong to any company. Create one to get started.',
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.all(ApexSpacing.xl),
                    children: [
                      Text(
                        'Choose a workspace',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select the company you want to work in.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: ApexSpacing.xl),
                      for (var i = 0; i < memberships.length; i++) ...[
                        if (i > 0) const SizedBox(height: ApexSpacing.md),
                        _CompanyTile(
                          membership: memberships[i],
                          colors: colors,
                          onTap: () => _select(memberships[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({
    required this.membership,
    required this.colors,
    required this.onTap,
  });
  final Membership membership;
  final ApexColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ApexRadius_lg),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(ApexSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(ApexRadius_md),
                ),
                child: Icon(
                  Icons.business_center_rounded,
                  color: colors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: ApexSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      membership.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      membership.gstin ?? membership.legalName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(ApexRadius_pill),
                    ),
                    child: Text(
                      membership.role.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(Icons.chevron_right_rounded, color: colors.textMuted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
