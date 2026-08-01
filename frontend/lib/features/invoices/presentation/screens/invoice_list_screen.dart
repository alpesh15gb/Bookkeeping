/// Invoice list screen — offline-first, design system.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/sync/sync_status.dart';
import '../../../../core/presentation/design_system/tokens/app_spacing.dart';
import '../../../../core/presentation/design_system/components/apex_card.dart';
import '../../../../core/presentation/design_system/components/apex_button.dart';
import '../../../../core/presentation/design_system/components/apex_status_badge.dart';
import '../../../../core/presentation/design_system/components/apex_states.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../invoices/domain/entities/invoice_entity.dart';
import '../providers/invoice_providers.dart';
import 'invoice_form_screen.dart';
import 'invoice_detail_screen.dart';

final _invoiceListProvider = StreamProvider.autoDispose((ref) {
  final companyId =
      ref.watch(authControllerProvider).activeMembership?.tenantId ?? '';
  return ref
      .watch(invoiceRepositoryProvider)
      .watchInvoices(companyId: companyId);
});

class InvoiceListScreen extends ConsumerStatefulWidget {
  const InvoiceListScreen({super.key});
  @override
  ConsumerState<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends ConsumerState<InvoiceListScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_invoiceListProvider);
    final colors = apexColors(context);
    final bp = ResponsiveLayout.of(context);
    final isMobile = bp.screenSize == ScreenSize.mobile;

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(
              isMobile ? AppSpacing.lg : AppSpacing.xxl,
              AppSpacing.xxl,
              isMobile ? AppSpacing.lg : AppSpacing.xxl,
              AppSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Invoices',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    ApexButton.primary(
                      label: 'New',
                      icon: const Icon(Icons.add_rounded, size: 18),
                      onPressed: () => _newDraft(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search invoices…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: colors.surfaceMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ],
            ),
          ),

          // ── List ───────────────────────────────────────────────────
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ApexErrorState(
                message: e.toString(),
                onRetry: () => ref.invalidate(_invoiceListProvider),
              ),
              data: (items) {
                final filtered = _search.isEmpty
                    ? items
                    : items
                          .where(
                            (i) =>
                                i.customerName.toLowerCase().contains(
                                  _search.toLowerCase(),
                                ) ||
                                (i.number?.toString() ?? '').contains(_search),
                          )
                          .toList();

                if (filtered.isEmpty) {
                  return ApexEmptyState(
                    title: items.isEmpty ? 'No invoices' : 'No matches',
                    subtitle: items.isEmpty
                        ? 'Create your first invoice.'
                        : 'Try a different search term.',
                    icon: Icons.receipt_long_outlined,
                    actionLabel: items.isEmpty ? 'New invoice' : null,
                    onAction: items.isEmpty ? () => _newDraft(context) : null,
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? AppSpacing.lg : AppSpacing.xxl,
                    0,
                    isMobile ? AppSpacing.lg : AppSpacing.xxl,
                    AppSpacing.xxl,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) =>
                      _invoiceCard(filtered[i], colors, isMobile),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _newDraft(BuildContext context) async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const InvoiceFormScreen()));
  }

  Widget _invoiceCard(InvoiceEntity inv, ApexColors colors, bool isMobile) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ApexCard(
        variant: ApexCardVariant.interactive,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InvoiceDetailScreen(localId: inv.localId),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    inv.isDraft
                        ? 'Draft'
                        : 'Invoice ${inv.displayNumber ?? '#${inv.number}'}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
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
                    const SizedBox(width: AppSpacing.xs),
                    ApexSyncBadge(
                      status: inv.syncStatus.name,
                      showLabel: false,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 14,
                  color: colors.textMuted,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    inv.customerName,
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '₹${inv.total.toRupees().toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (inv.syncError != null &&
                inv.syncStatus == SyncStatus.failed) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: colors.danger,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      inv.syncError!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colors.danger),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
