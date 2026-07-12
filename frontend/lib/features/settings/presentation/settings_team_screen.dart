/// Team management settings screen.
///
/// Lists team members with their roles and status. Supports inviting new
/// members, changing roles, and removing members.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/dialogs/dialog_service.dart';
import '../../../core/result/result.dart';
import '../../auth/data/models/membership_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/models/team_member.dart';
import 'settings_providers.dart';

class SettingsTeamScreen extends ConsumerStatefulWidget {
  const SettingsTeamScreen({super.key});

  @override
  ConsumerState<SettingsTeamScreen> createState() =>
      _SettingsTeamScreenState();
}

class _SettingsTeamScreenState extends ConsumerState<SettingsTeamScreen> {
  bool _isProcessing = false;

  String? get _companyId =>
      ref.read(authControllerProvider).activeMembership?.tenantId;

  Future<void> _inviteMember() async {
    final emailCtrl = TextEditingController();
    var selectedRole = MemberRole.accountant;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.person_add_outlined,
          size: 36,
          color: apexColors(context).primary,
        ),
        title: const Text('Invite Member'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email Address *',
                  prefixIcon: Icon(Icons.email_outlined),
                  hintText: 'colleague@company.com',
                ),
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<MemberRole>(
                value: selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Role *',
                  prefixIcon: Icon(Icons.shield_outlined),
                ),
                items: MemberRole.values
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(r.label),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) selectedRole = v;
                },
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (emailCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Send Invite'),
          ),
        ],
      ),
    );

    if (confirmed != true || emailCtrl.text.trim().isEmpty) {
      emailCtrl.dispose();
      return;
    }

    final companyId = _companyId;
    if (companyId == null) return;

    setState(() => _isProcessing = true);
    final repo = ref.read(settingsRepositoryProvider);
    final result = await repo.inviteMember(
      companyId,
      email: emailCtrl.text.trim(),
      role: selectedRole.wire,
    );
    setState(() => _isProcessing = false);
    emailCtrl.dispose();

    if (!mounted) return;
    if (result is Success<void>) {
      ref.invalidate(teamMemberListProvider(companyId));
      ref.read(notificationServiceProvider).success(
        context,
        'Invitation sent to ${emailCtrl.text}.',
        title: 'Invited',
      );
    } else {
      final err = (result as Failure<void>).error;
      ref.read(notificationServiceProvider).error(
        context,
        err.message,
        title: 'Invitation failed',
      );
    }
  }

  Future<void> _changeRole(TeamMember member) async {
    var newRole = member.role;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Role'),
        content: DropdownButtonFormField<MemberRole>(
          value: newRole,
          decoration: const InputDecoration(labelText: 'Role'),
          items: MemberRole.values
              .map(
                (r) => DropdownMenuItem(
                  value: r,
                  child: Text(r.label),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) newRole = v;
          },
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (confirmed != true || newRole == member.role) return;

    final companyId = _companyId;
    if (companyId == null) return;

    setState(() => _isProcessing = true);
    final repo = ref.read(settingsRepositoryProvider);
    final result = await repo.updateMemberRole(
      companyId,
      member.id,
      role: newRole.wire,
    );
    setState(() => _isProcessing = false);

    if (!mounted) return;
    if (result is Success<void>) {
      ref.invalidate(teamMemberListProvider(companyId));
      ref.read(notificationServiceProvider).success(
        context,
        '${member.displayName} role changed to ${newRole.label}.',
        title: 'Role Updated',
      );
    } else {
      final err = (result as Failure<void>).error;
      ref.read(notificationServiceProvider).error(
        context,
        err.message,
        title: 'Update failed',
      );
    }
  }

  Future<void> _removeMember(TeamMember member) async {
    final companyId = _companyId;
    if (companyId == null) return;

    final confirmed = await ref.read(dialogServiceProvider).confirmDelete(
      context,
      title: 'Remove member',
      message:
          'Are you sure you want to remove ${member.displayName} from the company?',
    );

    if (!confirmed) return;

    setState(() => _isProcessing = true);
    final repo = ref.read(settingsRepositoryProvider);
    final result = await repo.removeMember(companyId, member.id);
    setState(() => _isProcessing = false);

    if (!mounted) return;
    if (result is Success<void>) {
      ref.invalidate(teamMemberListProvider(companyId));
      ref.read(notificationServiceProvider).success(
        context,
        '${member.displayName} has been removed.',
        title: 'Removed',
      );
    } else {
      final err = (result as Failure<void>).error;
      ref.read(notificationServiceProvider).error(
        context,
        err.message,
        title: 'Removal failed',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final companyId = _companyId;

    if (companyId == null) {
      return const Center(child: Text('No company selected.'));
    }

    final async = ref.watch(teamMemberListProvider(companyId));

    return Scaffold(
      appBar: null,
      body: async.when(
        loading: () => const Center(child: LoadingSpinner(size: 36)),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(teamMemberListProvider(companyId)),
        ),
        data: (members) => _buildContent(colors, members),
      ),
    );
  }

  Widget _buildContent(ApexColors colors, List<TeamMember> members) {
    return Column(
      children: [
        PageHeader(
          title: 'Team',
          subtitle: 'Manage who has access to this company',
          actions: [
            FilledButton.icon(
              onPressed: _isProcessing ? null : _inviteMember,
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('Invite'),
            ),
          ],
        ),
        Expanded(
          child: members.isEmpty
              ? const EmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No team members',
                  subtitle: 'Invite your team to get started.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: members.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _buildMemberCard(colors, members[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildMemberCard(ApexColors colors, TeamMember member) {
    final statusTone = switch (member.invitationStatus) {
      InvitationStatus.active => StatusTone.success,
      InvitationStatus.pending => StatusTone.warning,
      InvitationStatus.expired => StatusTone.danger,
    };

    return ApexCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: colors.primary.withValues(alpha: 0.1),
            child: Text(
              member.displayName[0].toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.displayName,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(
                      label: member.role.label.toUpperCase(),
                      tone: StatusTone.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  member.email,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                StatusBadge(
                  label: member.invitationStatus.label.toUpperCase(),
                  tone: statusTone,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: colors.textMuted),
            onSelected: (action) {
              switch (action) {
                case 'change_role':
                  _changeRole(member);
                case 'remove':
                  _removeMember(member);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'change_role',
                child: ListTile(
                  leading: Icon(Icons.shield_outlined, size: 20),
                  title: Text('Change Role'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const PopupMenuItem(
                value: 'remove',
                child: ListTile(
                  leading: Icon(Icons.person_remove_outlined, size: 20),
                  title: Text('Remove'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
