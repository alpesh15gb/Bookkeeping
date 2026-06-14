import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';

class RecurringInvoiceListScreen extends StatelessWidget {
  const RecurringInvoiceListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Recurring Invoices', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Recurring Invoice', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AppFilterChip(label: 'All', count: 0, isSelected: true),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Active', count: 0),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Paused', count: 0),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Completed', count: 0),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppEmptyState(
            icon: Icons.repeat,
            title: 'No Recurring Invoices',
            subtitle: 'Set up templates to automatically generate invoices on a schedule',
          ),
        ),
      ],
    );
  }
}

class RecurringInvoiceFormScreen extends StatelessWidget {
  const RecurringInvoiceFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Recurring Invoice')),
      body: Center(
        child: AppEmptyState(
          icon: Icons.repeat,
          title: 'Recurring Invoice Form',
          subtitle: 'Create a recurring invoice template (coming soon)',
        ),
      ),
    );
  }
}

class RecurringInvoiceDetailScreen extends StatelessWidget {
  final String id;
  const RecurringInvoiceDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring Invoice Detail')),
      body: Center(
        child: AppEmptyState(
          icon: Icons.repeat,
          title: 'Recurring Invoice Detail',
          subtitle: 'View recurring invoice details (coming soon)',
        ),
      ),
    );
  }
}
