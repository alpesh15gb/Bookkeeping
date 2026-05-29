import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/auth_provider.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _gstinController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      final success = await context.read<AuthProvider>().register(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            fullName: _fullNameController.text.trim(),
            phoneNumber: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
            companyLegalName: _companyNameController.text.trim(),
            companyGstin: _gstinController.text.trim().isEmpty ? null : _gstinController.text.toUpperCase().trim(),
          );
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully. Please sign in.'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      } else if (mounted) {
        final error = context.read<AuthProvider>().errorMessage ?? 'Registration failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _companyNameController.dispose();
    _gstinController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgSidebar,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppShadows.dialog,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Set Up Your Business',
                      style: AppTextStyles.h1,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Enter your business details to get started",
                      style: AppTextStyles.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),

                    // Section: Business Information
                    const Text(
                      'BUSINESS INFORMATION',
                      style: AppTextStyles.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Full Name
                    TextFormField(
                      controller: _fullNameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Your Name *',
                        hintText: 'Enter your full name',
                        prefixIcon: Icon(Icons.person_outlined, size: 18),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 14),

                    // Company Name
                    TextFormField(
                      controller: _companyNameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Business Name *',
                        hintText: 'Enter your business name',
                        prefixIcon: Icon(Icons.business_outlined, size: 18),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Business name is required' : null,
                    ),
                    const SizedBox(height: 14),

                    // GSTIN + Phone
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _gstinController,
                            textInputAction: TextInputAction.next,
                            maxLength: 15,
                            decoration: InputDecoration(
                              labelText: 'GSTIN',
                              hintText: 'Optional',
                              prefixIcon: const Icon(Icons.pin_outlined, size: 18),
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneController,
                            textInputAction: TextInputAction.next,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'Phone',
                              hintText: 'Optional',
                              prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Email
                    TextFormField(
                      controller: _emailController,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email *',
                        hintText: 'Enter your email address',
                        prefixIcon: Icon(Icons.email_outlined, size: 18),
                      ),
                      validator: (v) => (v == null || !v.contains('@')) ? 'Invalid email' : null,
                    ),
                    const SizedBox(height: 14),

                    // Password
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password *',
                        hintText: 'Min 8 chars, mixed case, digit, special',
                        prefixIcon: const Icon(Icons.lock_outlined, size: 18),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 18,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.length < 8) return 'Password must be at least 8 characters';
                        if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Must contain an uppercase letter';
                        if (!RegExp(r'[a-z]').hasMatch(v)) return 'Must contain a lowercase letter';
                        if (!RegExp(r'\d').hasMatch(v)) return 'Must contain a digit';
                        if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>\-_=+\[\]\\/]').hasMatch(v)) return 'Must contain a special character';
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),

                    // Submit
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: authProvider.isLoading ? null : _submit,
                        child: authProvider.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.textWhite,
                                ),
                              )
                            : const Text('Create Account'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
