/// ApexBooks login screen.
///
/// Validates credentials client-side, calls [AuthController.login], and reacts
/// to loading / validation / network error states. Successful login hands off
/// to the router (which routes to company selection or the dashboard).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/index.dart'
    hide ApexTextField, ApexMonetaryField, ApexDropdownField;
import '../../../core/utils/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/form_fields.dart';
import 'auth_brand.dart';
import 'auth_controller.dart';
import 'auth_routes.dart' as auth_routes;

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final result = await ref
        .read(authControllerProvider.notifier)
        .login(_email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isFailure) {
      _showError(result.errorOrNull!.message);
    }
    // On success the router's redirect moves us to the right screen.
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
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthBrandHeader(),
            const SizedBox(height: ApexSpacing.xxl),
            Text(
              'Welcome back',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Sign in to your ApexBooks account',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: ApexSpacing.xl),
            ApexTextField(
              controller: _email,
              label: 'Email',
              hint: 'you@company.in',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.mail_outline_rounded,
              autofillHints: const [AutofillHints.email],
              validator: emailValidator,
            ),
            const SizedBox(height: ApexSpacing.lg),
            ApexPasswordField(
              controller: _password,
              label: 'Password',
              textInputAction: TextInputAction.go,
              autofillHints: const [AutofillHints.password],
              validator: (v) => requiredValidator(v, label: 'Password'),
              onFieldSubmitted: (_) => loading ? null : _submit(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: loading
                    ? null
                    : () => context.push(auth_routes.forgotPassword),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: ApexSpacing.sm),
            ApexSubmitButton(
              label: 'Sign in',
              icon: Icons.login_rounded,
              loading: loading,
              onPressed: loading ? null : _submit,
            ),
            const SizedBox(height: ApexSpacing.xl),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ApexSpacing.md,
                  ),
                  child: Text(
                    'or',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: ApexSpacing.xl),
            OutlinedButton(
              onPressed: loading
                  ? null
                  : () => context.go(auth_routes.register),
              child: const Text('Create a new account'),
            ),
          ],
        ),
      ),
    );
  }
}
