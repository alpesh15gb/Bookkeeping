/// Immutable invoice detail screen — design system.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/sync/sync_status.dart';
import '../../../../core/presentation/design_system/tokens/app_spacing.dart';
import '../../../../core/presentation/design_system/components/apex_card.dart';
import '../../../../core/presentation/design_system/components/apex_button.dart';
import '../../../../core/presentation/design_system/components/apex_status_badge.dart';
import '../../../../core/presentation/design_system/components/apex_states.dart';
import '../../../invoices/domain/entities/invoice_entity.dart';
import '../providers/invoice_providers.dart';
import 'invoice_form_screen.dart';

final _invoiceDetailProvider = FutureProvider.autoDispose
    .family<InvoiceEntity?, String>((ref, localId) {
      return ref.watch(invoiceRepositoryProvider).getInvoice(localId);
    });

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  const InvoiceDetailScreen({super.key, required this.localId});
  final String localId;
  @override
  ConsumerState<InvoiceDetailScreen> createState() =>
      _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final invoiceAsync = ref.watch(_invoiceDetailProvider(widget.localId));
    final theme = Theme.of(context);

    return invoiceAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: ApexErrorState(message: e.toString()),
      ),
      data: (inv) {
        if (inv == null) {
          return const Scaffold(
            body: Center(child: Text('Invoice not found.')),
          );
        }
        final colors = apexColors(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(
              inv.isDraft
                  ? 'Draft Invoice'
                  : 'Invoice ${inv.displayNumber ?? '#${inv.number ?? ''}'}',
            ),
            actions: [
              if (inv.isDraft)
                ApexButton.ghost(
                  label: 'Edit',
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const InvoiceFormScreen(),
                    ),
                  ),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (inv.isDraft)
                      const ApexStatusBadge(
                        label: 'Draft',
                        tone: ApexBadgeTone.neutral,
                        outlined: true,
                      )
                    else
                      const ApexStatusBadge(
                        label: 'Issued',
                        tone: ApexBadgeTone.success,
                      ),
                    const SizedBox(width: AppSpacing.sm),
                    ApexSyncBadge(status: inv.syncStatus.name),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),

                ApexCard(
                  padding: AppSpacing.lg,
                  child: Column(
                    children: [
                      _row('Customer', inv.customerName, Icons.person_rounded),
                      if (!inv.isDraft) ...[
                        const SizedBox(height: AppSpacing.md),
                        _row(
                          'Number',
                          inv.displayNumber ?? '#${inv.number ?? ''}',
                          Icons.tag_rounded,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      _row(
                        'Date',
                        inv.invoiceDate,
                        Icons.calendar_today_rounded,
                      ),
                      if (inv.dueDate != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        _row('Due', inv.dueDate!, Icons.event_rounded),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                Text('Line Items', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                ...inv.lines.map(
                  (l) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.productName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '×${l.quantity}',
                                style: TextStyle(
                                  color: colors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₹${Money.fromPaise(l.netPaise).toRupees().toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                _totalRow('Subtotal', Money.fromPaise(inv.totalBeforeTaxPaise)),
                if (inv.discountPaise > 0)
                  _totalRow('Discount', Money.fromPaise(-inv.discountPaise)),
                if (inv.taxPaise > 0)
                  _totalRow('GST', Money.fromPaise(inv.taxPaise)),
                const Divider(height: AppSpacing.lg),
                _totalRow('Total', Money.fromPaise(inv.totalPaise), bold: true),

                if (inv.syncStatus == SyncStatus.failed &&
                    inv.syncError != null) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  ApexCard(
                    variant: ApexCardVariant.danger,
                    padding: AppSpacing.md,
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 16),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            inv.syncError!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
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

  Widget _row(String label, String value, IconData icon) {
    final c = apexColors(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: c.textMuted),
        const SizedBox(width: AppSpacing.sm),
        Text('$label: ', style: TextStyle(color: c.textMuted)),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ],
    );
  }

  Widget _totalRow(String label, Money amount, {bool bold = false}) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            label,
            style: t.textTheme.bodyMedium?.copyWith(
              color: t.colorScheme.onSurfaceVariant,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          const SizedBox(width: AppSpacing.xxl),
          SizedBox(
            width: 120,
            child: Text(
              '₹${amount.toRupees().toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: (bold ? t.textTheme.titleMedium : t.textTheme.bodyLarge)
                  ?.copyWith(
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
