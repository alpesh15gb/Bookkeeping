/// Vendor Bill Empty State — Illustrated empty state with CTA.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';

class BillEmptyState extends StatelessWidget {
  const BillEmptyState({super.key, this.onCreate, this.onScan});

  final VoidCallback? onCreate;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    return Center(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 24 : 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Illustration
            Container(
              width: isMobile ? 120 : 160,
              height: isMobile ? 120 : 160,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: isMobile ? 60 : 80,
                color: colors.primary,
              ),
            ),

            const SizedBox(height: 24),

            // Title
            Text(
              'No Vendor Bills Yet',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Description
            Text(
              'Get started by creating or scanning your first vendor bill. '
              'Track payments, manage ITC, and stay GST compliant.',
              style: textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Action Buttons
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (onCreate != null)
                  ApexPrimaryButton(
                    icon: Icons.add,
                    label: 'Create Bill',
                    onPressed: onCreate,
                  ),
                if (onScan != null)
                  ApexSecondaryButton(
                    icon: Icons.document_scanner,
                    label: 'Scan Bill',
                    onPressed: onScan,
                  ),
              ],
            ),

            // Helpful links
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _HelpLink(
                  icon: Icons.article_outlined,
                  label: 'Bill Guide',
                  onTap: () {},
                ),
                _HelpLink(
                  icon: Icons.settings_outlined,
                  label: 'ITC Settings',
                  onTap: () {},
                ),
                _HelpLink(
                  icon: Icons.person_add_outlined,
                  label: 'Add Vendors',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpLink extends StatelessWidget {
  const _HelpLink({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colors.textSecondary),
            const SizedBox(width: 8),
            Text(label, style: textTheme.labelMedium?.copyWith(color: colors.textSecondary)),
          ],
        ),
      ),
    );
  }
}