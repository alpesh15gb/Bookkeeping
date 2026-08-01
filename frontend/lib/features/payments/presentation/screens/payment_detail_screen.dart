/// Payment detail screen — immutable posted payment view.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/sync/sync_status.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../offline_repository_providers.dart';
import '../../domain/commands/payment_commands.dart';
import '../../domain/entities/payment_entity.dart';
import 'package:apexbooks/core/errors/user_message.dart';

final _paymentDetailProvider = FutureProvider.autoDispose
    .family<PaymentEntity?, String>((ref, localId) {
      return ref.watch(paymentRepositoryProvider).getPayment(localId);
    });

class PaymentDetailScreen extends ConsumerWidget {
  const PaymentDetailScreen({super.key, required this.localId});
  final String localId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentAsync = ref.watch(_paymentDetailProvider(localId));
    final colors = apexColors(context);

    return paymentAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Payment')),
        body: Center(child: Text('Error: $e')),
      ),
      data: (p) {
        if (p == null) {
          return const Scaffold(
            body: Center(child: Text('Payment not found.')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(p.isDraft ? 'Draft Payment' : 'Payment'),
            actions: [
              if (p.isDraft)
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      final companyId = ref
                          .read(authControllerProvider)
                          .activeMembership
                          ?.tenantId;
                      await ref
                          .read(paymentRepositoryProvider)
                          .post(
                            PostPaymentCommand(
                              localId: p.localId,
                              companyId: companyId ?? p.companyId,
                            ),
                          );
                      ref.invalidate(_paymentDetailProvider(localId));
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(error))));
                    }
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Post'),
                ),
              const SizedBox(width: 12),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(
                      label: p.isDraft ? 'Draft' : 'Posted',
                      tone: p.isDraft ? StatusTone.neutral : StatusTone.success,
                    ),
                    const SizedBox(width: 8),
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
                const SizedBox(height: 24),
                _row(
                  'Type',
                  p.isReceipt ? 'Receipt' : 'Payment',
                  Icons.swap_horiz_rounded,
                  colors,
                ),
                const SizedBox(height: 12),
                _row(
                  'Date',
                  p.paymentDate,
                  Icons.calendar_today_rounded,
                  colors,
                ),
                const SizedBox(height: 12),
                _row('Contact', p.contactName, Icons.person_rounded, colors),
                const SizedBox(height: 12),
                _row('Mode', p.paymentMode, Icons.payment_rounded, colors),
                const SizedBox(height: 12),
                _row(
                  'Amount',
                  '₹${p.amount.toRupees().toStringAsFixed(2)}',
                  Icons.money_rounded,
                  colors,
                  bold: true,
                ),
                if (p.syncStatus == SyncStatus.failed &&
                    p.syncError != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      p.syncError!,
                      style: TextStyle(color: colors.danger, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(
    String label,
    String value,
    IconData icon,
    ApexColors colors, {
    bool bold = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: colors.textMuted),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: colors.textMuted,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            fontSize: bold ? 18 : 15,
          ),
        ),
      ],
    );
  }
}
