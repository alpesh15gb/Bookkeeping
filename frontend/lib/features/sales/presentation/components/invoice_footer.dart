/// Invoice Footer — Notes, terms, and action buttons.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import '../invoice_form_notifier.dart';
import '../invoice_form_state.dart';

class InvoiceFooter extends ConsumerWidget {
  const InvoiceFooter({
    super.key,
    required this.state,
    required this.notifier,
    required this.fmt,
  });

  final InvoiceFormState state;
  final InvoiceFormNotifier notifier;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    return ApexCard(
      elevation: CardElevation.low,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Text('Additional Details', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
          const SizedBox(height: 16),

          // Notes
          ApexTextField(
            label: 'Notes',
            controller: null,
            initialValue: state.notes ?? '',
            hint: 'Internal notes (not shown to customer)',
            maxLines: 3,
            onChanged: notifier.setNotes,
          ),

          const SizedBox(height: 16),

          // Terms & Conditions
          ApexTextField(
            label: 'Terms & Conditions',
            controller: null,
            initialValue: state.termsAndConditions ?? '',
            hint: 'Payment terms, delivery terms, etc. (shown on invoice)',
            maxLines: 3,
            onChanged: notifier.setTermsAndConditions,
          ),

          const SizedBox(height: 20),

          // Action Buttons (shown on desktop, hidden on mobile since mobile has fixed footer)
          if (!isMobile) ...[
            Divider(color: colors.border, height: 1),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ApexSecondaryButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
                ApexPrimaryButton(
                  label: state.isSaving ? 'Saving...' : 'Save Invoice',
                  onPressed: state.isSaving ? null : () => _save(context, notifier),
                  isLoading: state.isSaving,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context, InvoiceFormNotifier notifier) async {
    final result = await notifier.save();
    if (!context.mounted) return;

    switch (result) {
      case Success(:final value):
        ApexSnackBar.show(
          context: context,
          message: 'Invoice saved successfully',
          type: SnackBarType.success,
        );
        Navigator.of(context).pop(value);
      case Failure(:final error):
        ApexSnackBar.show(
          context: context,
          message: 'Failed to save: ${error.message}',
          type: SnackBarType.error,
        );
      default:
        break;
    }
  }
}