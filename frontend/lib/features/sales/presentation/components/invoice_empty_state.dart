/// Invoice Empty State — Illustrated empty state with CTA.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';

class InvoiceEmptyState extends StatelessWidget {
  const InvoiceEmptyState({super.key, this.onCreate});

  final VoidCallback? onCreate;

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
              'No Invoices Yet',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Description
            Text(
              'Get started by creating your first sales invoice. '
              'Track payments, manage GST, and stay organized.',
              style: textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Action Button
            if (onCreate != null)
              ApexPrimaryButton(
                icon: Icons.add,
                label: 'Create First Invoice',
                onPressed: onCreate,
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
                  label: 'Invoice Guide',
                  onTap: () {},
                ),
                _HelpLink(
                  icon: Icons.settings_outlined,
                  label: 'GST Settings',
                  onTap: () {},
                ),
                _HelpLink(
                  icon: Icons.person_add_outlined,
                  label: 'Add Customers',
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