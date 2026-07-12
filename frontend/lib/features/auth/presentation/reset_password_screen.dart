/// Reset-password screen — submits the token (from the email link) + new
/// password to [AuthController.resetPassword].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/form_fields.dart';
import '../data/models/auth_requests.dart';
import 'auth_brand.dart';
import 'auth_controller.dart';
import 'auth_routes.dart' as auth_routes;

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.initialToken});
  final String? initialToken;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _token = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialToken != null) _token.text = widget.initialToken!;
  }

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final result = await ref
        .read(authControllerProvider.notifier)
        .resetPassword(
          ResetPasswordRequest(
            token: _token.text.trim(),
            newPassword: _password.text,
          ),
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      setState(() => _done = true);
    } else {
      _showError(result.errorOrNull!.message);
    }
  }

  void _showError(String message) {
    final colors = apexColors(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final loading = ref.watch(authControllerProvider).isLoading || _submitting;
    return AuthScaffold(
      child: _done
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_reset_rounded, size: 48, color: colors.success),
                const SizedBox(height: ApexSpacing.lg),
                Text(
                  'Password updated',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: ApexSpacing.sm),
                Text(
                  'Your password has been reset. You can sign in now.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: ApexSpacing.xl),
                ApexSubmitButton(
                  label: 'Back to sign in',
                  icon: Icons.login_rounded,
                  onPressed: () => context.go(auth_routes.login),
                ),
              ],
            )
          : Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthBrandHeader(tagline: 'Account recovery'),
                  const SizedBox(height: ApexSpacing.xxl),
                  Text(
                    'Set a new password',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Paste the reset token from your email and choose a new password.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: ApexSpacing.xl),
                  ApexTextField(
                    controller: _token,
                    label: 'Reset token',
                    hint: 'Paste the token from your email',
                    textInputAction: TextInputAction.next,
                    prefixIcon: Icons.key_outlined,
                    validator: (v) => requiredValidator(v, label: 'Token'),
                  ),
                  const SizedBox(height: ApexSpacing.lg),
                  ApexPasswordField(
                    controller: _password,
                    label: 'New password',
                    textInputAction: TextInputAction.go,
                    validator: passwordValidator,
                    onFieldSubmitted: (_) => loading ? null : _submit(),
                  ),
                  const SizedBox(height: ApexSpacing.xl),
                  ApexSubmitButton(
                    label: 'Reset password',
                    icon: Icons.lock_reset_rounded,
                    loading: loading,
                    onPressed: loading ? null : _submit,
                  ),
                  const SizedBox(height: ApexSpacing.lg),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => context.go(auth_routes.login),
                    child: const Text('Back to sign in'),
                  ),
                ],
              ),
            ),
    );
  }
}
