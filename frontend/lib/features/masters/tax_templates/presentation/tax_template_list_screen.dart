/// Tax Template list screen — shows seeded GST rate templates.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../data/models/tax_template.dart';
import 'tax_template_provider.dart';

class TaxTemplateListScreen extends ConsumerWidget {
  const TaxTemplateListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(taxTemplateListProvider);

    return Scaffold(
      appBar: null,
      body: async.when(
        loading: () => const Center(child: LoadingSpinner(size: 36)),
        error: (err, _) => ErrorView(
          message: userFacingErrorMessage(err),
          onRetry: () => ref.invalidate(taxTemplateListProvider),
        ),
        data: (templates) => templates.isEmpty
            ? const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No tax templates',
                subtitle: 'Standard GST rates will be seeded automatically.',
              )
            : _templateList(context, templates),
      ),
    );
  }

  Widget _templateList(BuildContext context, List<TaxTemplate> templates) {
    final colors = apexColors(context);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: templates.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final t = templates[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: colors.primary.withValues(alpha: 0.1),
            child: Text(
              '${t.rate.toInt()}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
          ),
          title: Text(t.name),
          trailing: Text(
            '${t.rate.toStringAsFixed(2)}%',
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}
