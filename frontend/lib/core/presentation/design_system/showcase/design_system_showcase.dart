/// Design system showcase — development-only screen.
library;

import 'package:flutter/material.dart';
import '../components/apex_button.dart';
import '../components/apex_card.dart';
import '../components/apex_status_badge.dart';
import '../components/apex_states.dart';
import '../tokens/app_spacing.dart';

class DesignSystemShowcase extends StatelessWidget {
  const DesignSystemShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Design System')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Typography
          _section(context, 'Typography'),
          Text('Display Large', style: theme.textTheme.displayLarge),
          Text('Display Medium', style: theme.textTheme.displayMedium),
          Text('Headline Large', style: theme.textTheme.headlineLarge),
          Text('Headline Medium', style: theme.textTheme.headlineMedium),
          Text('Headline Small', style: theme.textTheme.headlineSmall),
          Text('Title Large', style: theme.textTheme.titleLarge),
          Text('Title Medium', style: theme.textTheme.titleMedium),
          Text('Body Large', style: theme.textTheme.bodyLarge),
          Text('Body Medium', style: theme.textTheme.bodyMedium),
          Text('Body Small', style: theme.textTheme.bodySmall),
          Text('Label', style: theme.textTheme.labelLarge),

          const SizedBox(height: AppSpacing.xxl),

          // Colors
          _section(context, 'Colors'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _colorSwatch('Primary', theme.colorScheme.primary),
              _colorSwatch('Surface', theme.colorScheme.surface),
              _colorSwatch('Error', theme.colorScheme.error),
              _colorSwatch('Success', Colors.green),
              _colorSwatch('Warning', Colors.orange),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Buttons
          _section(context, 'Buttons'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              const ApexButton.primary(label: 'Primary'),
              const ApexButton.secondary(label: 'Secondary'),
              const ApexButton.danger(label: 'Danger'),
              const ApexButton.ghost(label: 'Ghost'),
              ApexButton.primary(
                label: 'Loading',
                loading: true,
                onPressed: () {},
              ),
              const ApexButton.primary(label: 'Full width', fullWidth: false),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Cards
          _section(context, 'Cards'),
          const ApexCard(child: Text('Standard card')),
          const SizedBox(height: AppSpacing.sm),
          const ApexCard(
            variant: ApexCardVariant.highlighted,
            child: Text('Highlighted card'),
          ),
          const SizedBox(height: AppSpacing.sm),
          const ApexCard(
            variant: ApexCardVariant.danger,
            child: Text('Danger card'),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // KPI
          _section(context, 'KPI Cards'),
          const Row(
            children: [
              Expanded(
                child: ApexKpiCard(
                  label: 'Revenue',
                  value: '₹2,45,000',
                  icon: Icons.trending_up,
                  trend: 12.5,
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: ApexKpiCard(
                  label: 'Expenses',
                  value: '₹1,20,000',
                  icon: Icons.trending_down,
                  trend: -3.2,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Badges
          _section(context, 'Badges'),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ApexStatusBadge(label: 'Success', tone: ApexBadgeTone.success),
              ApexStatusBadge(label: 'Warning', tone: ApexBadgeTone.warning),
              ApexStatusBadge(label: 'Danger', tone: ApexBadgeTone.danger),
              ApexStatusBadge(label: 'Info', tone: ApexBadgeTone.info),
              ApexStatusBadge(label: 'Pending', tone: ApexBadgeTone.pending),
              ApexStatusBadge(label: 'Syncing', tone: ApexBadgeTone.syncing),
              ApexSyncBadge(status: 'synced'),
              ApexSyncBadge(status: 'pending', count: 3),
              ApexSyncBadge(status: 'failed'),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          // States
          _section(context, 'States'),
          SizedBox(
            height: 200,
            child: ApexEmptyState(
              title: 'No invoices found',
              subtitle: 'Create your first invoice to get started.',
              icon: Icons.receipt_long_outlined,
              actionLabel: 'New invoice',
              onAction: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm, top: AppSpacing.md),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _colorSwatch(String name, Color color) => Tooltip(
    message: name,
    child: Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
    ),
  );
}
