/// Payment list screen — offline-first.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/states.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/sync/sync_status.dart';
import '../../../offline_repository_providers.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../payments/domain/entities/payment_entity.dart';
import 'payment_form_screen.dart';
import 'payment_detail_screen.dart';
import 'package:apexbooks/core/errors/user_message.dart';

final _paymentListProvider = StreamProvider.autoDispose((ref) {
  final companyId =
      ref.watch(authControllerProvider).activeMembership?.tenantId ?? '';
  return ref
      .watch(paymentRepositoryProvider)
      .watchPayments(companyId: companyId);
});

class PaymentListScreen extends ConsumerWidget {
  const PaymentListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_paymentListProvider);
    final colors = apexColors(context);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Payments',
            subtitle: 'Receipts and payments — local until synced.',
            actions: [
              FilledButton.icon(
                onPressed: () => _newPayment(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New payment'),
              ),
            ],
          ),
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(_paymentListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.payments_outlined,
                    title: 'No payments',
                    subtitle: 'Record a receipt or payment.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _paymentCard(items[i], colors, ref),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _newPayment(BuildContext context) async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const PaymentFormScreen()));
  }

  Widget _paymentCard(PaymentEntity p, ApexColors colors, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(ref.context).push(
          MaterialPageRoute(
            builder: (_) => PaymentDetailScreen(localId: p.localId),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    p.isReceipt
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 20,
                    color: p.isReceipt ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.contactName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  StatusBadge(
                    label: p.isDraft ? 'Draft' : 'Posted',
                    tone: p.isDraft ? StatusTone.neutral : StatusTone.success,
                  ),
                  const SizedBox(width: 4),
                  StatusBadge(
                    label: p.syncStatus.label,
                    tone: p.syncStatus == SyncStatus.synced
                        ? StatusTone.success
                        : p.syncStatus.requiresAttention
                        ? StatusTone.danger
                        : StatusTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    p.paymentDate,
                    style: TextStyle(color: colors.textMuted),
                  ),
                  const Spacer(),
                  Text(
                    '₹${p.amount.toRupees().toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
