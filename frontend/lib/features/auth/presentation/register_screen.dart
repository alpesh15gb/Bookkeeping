/// ApexBooks registration screen.
///
/// Collects account + first company details, validates against the backend
/// rules (password policy, GSTIN/PAN patterns), and calls
/// [AuthController.register], which auto-logs the user in on success.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/index.dart'
    hide ApexTextField, ApexMonetaryField, ApexDropdownField;
import '../../../core/utils/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/form_fields.dart';
import '../data/models/auth_requests.dart';
import 'auth_brand.dart';
import 'auth_controller.dart';
import 'auth_routes.dart' as auth_routes;
import 'register_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _companyName = TextEditingController();
  final _gstin = TextEditingController();
  final _pan = TextEditingController();
  bool _submitting = false;
  bool _showCompanyFields = true;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _companyName.dispose();
    _gstin.dispose();
    _pan.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_companyName.text.trim().isEmpty) {
      setState(() => _showCompanyFields = true);
      _showError('Enter your company legal name.');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final result = await ref
        .read(authControllerProvider.notifier)
        .register(
          RegisterRequest(
            email: _email.text.trim(),
            password: _password.text,
            fullName: _fullName.text.trim(),
            phoneNumber: _phone.text.trim(),
            companyLegalName: _companyName.text.trim(),
            companyGstin: _gstin.text.trim().isNotEmpty
                ? _gstin.text.trim().toUpperCase()
                : null,
            companyPan: _pan.text.trim().isNotEmpty
                ? _pan.text.trim().toUpperCase()
                : null,
          ),
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isFailure) _showError(result.errorOrNull!.message);
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
              'Create your account',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Start managing your books in minutes',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: ApexSpacing.xl),
            ApexTextField(
              controller: _fullName,
              label: 'Full name',
              hint: 'Ramesh Kumar',
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.person_outline_rounded,
              validator: (v) => requiredValidator(v, label: 'Full name'),
            ),
            const SizedBox(height: ApexSpacing.lg),
            ApexTextField(
              controller: _email,
              label: 'Email',
              hint: 'you@company.in',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.mail_outline_rounded,
              validator: emailValidator,
            ),
            const SizedBox(height: ApexSpacing.lg),
            ApexTextField(
              controller: _phone,
              label: 'Phone (optional)',
              hint: '+91 98765 43210',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.phone_outlined,
              validator: phoneValidator,
            ),
            const SizedBox(height: ApexSpacing.lg),
            ApexPasswordField(
              controller: _password,
              label: 'Password',
              textInputAction: TextInputAction.next,
              validator: passwordValidator,
            ),
            const SizedBox(height: ApexSpacing.sm),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _password,
              builder: (context, value, _) =>
                  PasswordStrengthBar(password: value.text),
            ),
            const SizedBox(height: ApexSpacing.lg),
            CompanyFieldsSection(
              showFields: _showCompanyFields,
              onToggle: () =>
                  setState(() => _showCompanyFields = !_showCompanyFields),
              companyName: _companyName,
              gstin: _gstin,
              pan: _pan,
            ),
            const SizedBox(height: ApexSpacing.lg),
            ApexSubmitButton(
              label: 'Create account',
              icon: Icons.person_add_alt_rounded,
              loading: loading,
              onPressed: loading ? null : _submit,
            ),
            const SizedBox(height: ApexSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Already have an account?',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
                TextButton(
                  onPressed: loading
                      ? null
                      : () => context.go(auth_routes.login),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
