/// Shared settings page layout — consistent header, sections, and save button.
library;

import 'package:flutter/material.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';
import 'apex_button.dart';

class SettingsPageLayout extends StatelessWidget {
  const SettingsPageLayout({
    super.key,
    required this.title,
    this.subtitle,
    this.sections = const [],
    this.saveLabel = 'Save',
    this.onSave,
    this.isSaving = false,
    this.error,
    this.children = const [],
  });

  final String title;
  final String? subtitle;
  final List<SettingsSection> sections;
  final String saveLabel;
  final VoidCallback? onSave;
  final bool isSaving;
  final String? error;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────
          Text(title, style: theme.textTheme.headlineSmall),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),

          // ── Sections ──────────────────────────────────────────────
          ...sections,
          ...children,

          // ── Error ─────────────────────────────────────────────────
          if (error != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                error!,
                style: AppTypography.validationError.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],

          // ── Save button ───────────────────────────────────────────
          if (onSave != null) ...[
            const SizedBox(height: AppSpacing.xxl),
            ApexButton.primary(
              label: isSaving ? 'Saving…' : saveLabel,
              onPressed: onSave,
              loading: isSaving,
              fullWidth: true,
            ),
          ],
        ],
      ),
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    this.children = const [],
    this.padding = AppSpacing.lg,
  });

  final String title;
  final List<Widget> children;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.sectionTitle.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsField extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.label,
    this.initialValue,
    this.controller,
    this.onChanged,
    this.validator,
    this.keyboardType,
    this.hintText,
    this.readOnly = false,
    this.maxLines = 1,
    this.prefixIcon,
    this.suffix,
    this.helperText,
  });

  final String label;
  final String? initialValue;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final String? hintText;
  final bool readOnly;
  final int maxLines;
  final IconData? prefixIcon;
  final Widget? suffix;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: controller,
        initialValue: initialValue,
        onChanged: onChanged,
        validator: validator,
        keyboardType: keyboardType,
        readOnly: readOnly,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18) : null,
          suffixIcon: suffix,
          helperText: helperText,
          helperMaxLines: 2,
        ),
      ),
    );
  }
}
