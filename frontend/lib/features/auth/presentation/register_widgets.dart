/// Helper widgets for the registration screen: the password-strength meter
/// and the collapsible company-details section.
library;

import 'package:flutter/material.dart';

import '../../../core/design_system/index.dart'
    hide ApexTextField, ApexMonetaryField, ApexDropdownField;
import '../../../core/utils/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/form_fields.dart';

/// A 0-100 password strength bar derived from the ApexBooks password policy.
class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({super.key, required this.password});
  final String password;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final score = passwordStrength(password);
    if (score == 0) return const SizedBox.shrink();

    final (label, color) = switch (score) {
      < 40 => ('Weak', colors.danger),
      < 70 => ('Fair', colors.warning),
      < 90 => ('Good', colors.info),
      _ => ('Strong', colors.success),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(ApexRadius_pill),
          child: LinearProgressIndicator(
            value: score / 100,
            minHeight: 5,
            backgroundColor: colors.surfaceMuted,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Password strength: $label',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// Collapsible section collecting the first company's legal name, GSTIN, PAN.
class CompanyFieldsSection extends StatelessWidget {
  const CompanyFieldsSection({
    super.key,
    required this.showFields,
    required this.onToggle,
    required this.companyName,
    required this.gstin,
    required this.pan,
  });

  final bool showFields;
  final VoidCallback onToggle;
  final TextEditingController companyName;
  final TextEditingController gstin;
  final TextEditingController pan;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(ApexRadius_md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  showFields
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Company details',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  'Required',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
        ),
        if (showFields) ...[
          const SizedBox(height: ApexSpacing.md),
          ApexTextField(
            controller: companyName,
            label: 'Company legal name',
            hint: 'ABC Traders Pvt Ltd',
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            prefixIcon: Icons.business_outlined,
            validator: (v) => requiredValidator(v, label: 'Company name'),
          ),
          const SizedBox(height: ApexSpacing.lg),
          ApexTextField(
            controller: gstin,
            label: 'GSTIN (optional)',
            hint: '29AABCT1332L1ZP',
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            prefixIcon: Icons.receipt_long_outlined,
            validator: gstinValidator,
          ),
          const SizedBox(height: ApexSpacing.lg),
          ApexTextField(
            controller: pan,
            label: 'PAN (optional)',
            hint: 'AABCT1332L',
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            prefixIcon: Icons.badge_outlined,
            validator: panValidator,
          ),
        ],
      ],
    );
  }
}
