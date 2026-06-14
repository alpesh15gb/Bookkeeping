import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().fetchAllSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final company = settings.company;
    final isLoading = settings.isLoading;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: AppTypography.headlineLarge),
          const SizedBox(height: AppSpacing.sectionGap),

          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(title: 'COMPANY PROFILE'),
                const SizedBox(height: AppSpacing.lg),
                if (isLoading)
                  const AppLoadingRow()
                else ...[
                  _buildInfoRow('Legal Name', company['legal_name'] ?? company['name'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('Trade Name', company['trade_name'] ?? company['name'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('Phone', company['phone'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('Email', company['email'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('Website', company['website'] ?? '-'),
                ],
                const SizedBox(height: AppSpacing.md),
                AppButton(label: 'Edit Profile', icon: Icons.edit, style: AppButtonStyle.secondary, onPressed: () {}),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(title: 'TAX & COMPLIANCE'),
                const SizedBox(height: AppSpacing.lg),
                if (isLoading)
                  const AppLoadingRow()
                else ...[
                  _buildInfoRow('GSTIN', company['gstin'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('PAN', company['pan'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('State', company['state'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('Tax Mode', settings.taxMode),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(title: 'PREFERENCES'),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Dark Mode', style: AppTypography.bodySmall),
                    Switch(
                      value: themeProvider.isDarkMode,
                      onChanged: (_) => themeProvider.toggleTheme(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodySmall),
        Text(value, style: AppTypography.labelMedium),
      ],
    );
  }
}
