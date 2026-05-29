import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/auth_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';

class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _isSending = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);
    final provider = context.read<AuthProvider>();
    final success = await provider.forgotPassword(_emailCtrl.text.trim());
    if (mounted) {
      setState(() => _isSending = false);
      if (success) {
        setState(() => _sent = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Failed to send reset email'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: const Text('Forgot Password')),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Form(
          key: _formKey,
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_sent) ...[
                  const Icon(Icons.check_circle_outline, size: 48, color: AppColors.success),
                  const SizedBox(height: 16),
                  const Text('Check your email', style: AppTextStyles.h2, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text('If an account exists with that email, you will receive a password reset link.', style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to Login'),
                    ),
                  ),
                ] else ...[
                  Text(
                    'Enter your email address and we\'ll send you a link to reset your password.',
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined, size: 18),
                    ),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _isSending ? null : _submit,
                      child: _isSending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send Reset Link'),
                    ),
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
