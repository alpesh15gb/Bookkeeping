/// Payment Term list screen — shows seeded payment terms.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import '../data/models/payment_term.dart';
import 'payment_term_provider.dart';

class PaymentTermListScreen extends ConsumerWidget {
  const PaymentTermListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(paymentTermListProvider);

    return Scaffold(
      appBar: null,
      body: async.when(
        loading: () => const Center(child: LoadingSpinner(size: 36)),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(paymentTermListProvider),
        ),
        data: (terms) => terms.isEmpty
            ? const EmptyState(
                icon: Icons.schedule_outlined,
                title: 'No payment terms',
                subtitle: 'Standard terms will be seeded automatically.',
              )
            : _termList(context, terms),
      ),
    );
  }

  Widget _termList(BuildContext context, List<PaymentTerm> terms) {
    final colors = apexColors(context);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: terms.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final t = terms[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: colors.primary.withValues(alpha: 0.1),
            child: Icon(Icons.event_outlined, size: 18, color: colors.primary),
          ),
          title: Text(t.name),
          subtitle: Text(
            t.dueDays == 0 ? 'Due on receipt' : 'Due in ${t.dueDays} days',
          ),
          trailing: Text(
            '${t.dueDays}d',
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}
