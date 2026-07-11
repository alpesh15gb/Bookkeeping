/// Declarative permission gating. Use [PermissionGate] instead of
/// `if (canEdit)` checks scattered through build methods.
///
///   ```dart
///   PermissionGate(
///     permission: Permissions.invoiceFinalize,
///     fallback: SizedBox.shrink(),
///     child: FilledButton(onPressed: finalize, child: Text('Finalize')),
///   )
///   ```
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../permissions/permissions.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/data/models/membership_models.dart';

/// A [Provider] exposing whether the active role grants a given permission.
/// Computed once per permission string and re-evaluated when the active
/// membership changes.
final permissionProvider = Provider.family<bool, String>((ref, permission) {
  final auth = ref.watch(authControllerProvider);
  final role = auth.activeMembership?.role;
  if (role == null) return false;
  return hasPermission(role, permission);
});

/// A widget that shows [child] only when the active role has [permission];
/// otherwise it shows [fallback] (default: nothing).
class PermissionGate extends ConsumerWidget {
  const PermissionGate({
    super.key,
    required this.permission,
    required this.child,
    this.fallback = const SizedBox.shrink(),
  });

  final String permission;
  final Widget child;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final granted = ref.watch(permissionProvider(permission));
    return granted ? child : fallback;
  }
}

/// Returns `true` when the active role grants [permission]. Use inside event
/// handlers / controllers where a widget isn't appropriate.
bool canPerform(WidgetRef ref, String permission) =>
    ref.read(permissionProvider(permission));

/// Returns the active [MemberRole] (or `null` when not signed in / no tenant).
MemberRole? activeRole(WidgetRef ref) =>
    ref.read(authControllerProvider).activeMembership?.role;
