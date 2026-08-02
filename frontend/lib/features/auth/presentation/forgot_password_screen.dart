/// Forgot-password screen — requests a reset email via [AuthController].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/index.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/form_fields.dart' show ApexSubmitButton;
import 'auth_brand.dart';
import 'auth_controller.dart';
import 'auth_routes.dart' as auth_routes;

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _submitting = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final result = await ref
        .read(authControllerProvider.notifier)
        .forgotPassword(_email.text.trim());
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      setState(() => _sent = true);
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
      child: _sent
          ? _SuccessView(
              email: _email.text.trim(),
              onBack: () => context.go(auth_routes.login),
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
                    'Forgot password?',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter your email and we\'ll send you a reset link.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: ApexSpacing.xl),
                  ApexTextField(
                    controller: _email,
                    label: 'Email',
                    hint: 'you@company.in',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    prefixIcon: Icons.mail_outline_rounded,
                    validator: emailValidator,
                    onFieldSubmitted: (_) => loading ? null : _submit(),
                  ),
                  const SizedBox(height: ApexSpacing.xl),
                  ApexSubmitButton(
                    label: 'Send reset link',
                    icon: Icons.send_rounded,
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

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.email, required this.onBack});
  final String email;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colors.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.mark_email_read_outlined,
            size: 30,
            color: colors.success,
          ),
        ),
        const SizedBox(height: ApexSpacing.lg),
        Text(
          'Check your email',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: ApexSpacing.sm),
        Text(
          'We sent a password reset link to\n$email',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: ApexSpacing.xl),
        ApexSubmitButton(
          label: 'Back to sign in',
          icon: Icons.arrow_back_rounded,
          onPressed: onBack,
        ),
      ],
    );
  }
}
