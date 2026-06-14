import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';

class TermsTemplatesScreen extends StatelessWidget {
  const TermsTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Terms Templates', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Template', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppEmptyState(
            icon: Icons.description_outlined,
            title: 'No Terms Templates',
            subtitle: 'Create reusable terms & conditions templates for your invoices',
          ),
        ),
      ],
    );
  }
}
