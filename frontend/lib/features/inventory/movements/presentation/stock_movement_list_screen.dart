import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart' hide ApexCard;
import 'package:apexbooks/core/widgets/search_bar.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/features/inventory/stock/models/stock_models.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import 'stock_movement_list_provider.dart';

class StockMovementListScreen extends ConsumerStatefulWidget {
  const StockMovementListScreen({super.key});
  @override
  ConsumerState<StockMovementListScreen> createState() =>
      _StockMovementListScreenState();
}

class _StockMovementListScreenState
    extends ConsumerState<StockMovementListScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  MovementReferenceType? _typeFilter;

  static String _typeLabel(MovementReferenceType t) => switch (t) {
    MovementReferenceType.invoice => 'Sale',
    MovementReferenceType.bill => 'Purchase',
    MovementReferenceType.adjustment => 'Adjustment',
    MovementReferenceType.transfer => 'Transfer',
    MovementReferenceType.opening => 'Opening',
    MovementReferenceType.salesReturn => 'Sales Return',
    MovementReferenceType.purchaseReturn => 'Purchase Return',
    MovementReferenceType.creditNote => 'Credit Note Return',
    MovementReferenceType.deliveryChallan => 'Delivery Challan',
    MovementReferenceType.invoiceReversal => 'Invoice Reversal',
    MovementReferenceType.billReversal => 'Purchase Reversal',
    MovementReferenceType.adjustmentReversal => 'Adjustment Reversal',
    MovementReferenceType.salesReturnReversal => 'Sales Return Reversal',
    MovementReferenceType.purchaseReturnReversal => 'Purchase Return Reversal',
    MovementReferenceType.creditNoteReversal => 'Credit Note Reversal',
    MovementReferenceType.deliveryChallanReversal => 'Challan Reversal',
    MovementReferenceType.migrationReconcile => 'Opening Reconciliation',
  };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      stockMovementsProvider(MovementQuery(referenceType: _typeFilter)),
    );
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          const PageHeader(
            title: 'Stock Ledger',
            subtitle: 'Complete audit trail of every stock movement.',
          ),
          _toolbar(colors, isMobile),
          Expanded(
            child: async.when(
              loading: () => ShimmerSkeleton(
                child: Column(
                  children: [
                    for (int i = 0; i < 6; i++)
                      const TableRowSkeleton(columns: 4),
                  ],
                ),
              ),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(stockMovementsProvider),
              ),
              data: (items) {
                final q = _search.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? items
                    : items
                          .where((m) => m.productName.toLowerCase().contains(q))
                          .toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.swap_vert_rounded,
                    title: items.isEmpty
                        ? 'No stock movements yet'
                        : 'No matching movements',
                    subtitle: items.isEmpty
                        ? 'Movements are recorded automatically from invoices, bills, adjustments and transfers.'
                        : 'Try a different search or filter.',
                  );
                }
                return isMobile
                    ? _mobileList(filtered, colors, fmt)
                    : _table(filtered, colors, fmt);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(ApexColors colors, bool isMobile) {
    final search = ApexSearchBar(
      controller: _searchCtrl,
      hintText: 'Search product…',
      onChanged: (v) => setState(() => _search = v),
    );
    final dropdown = _typeDropdown(colors);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? ApexSpacing.md : ApexSpacing.xl,
        0,
        isMobile ? ApexSpacing.md : ApexSpacing.xl,
        ApexSpacing.md,
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: ApexSpacing.sm),
                Align(alignment: Alignment.centerLeft, child: dropdown),
              ],
            )
          : Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: ApexSpacing.md),
                dropdown,
              ],
            ),
    );
  }

  Widget _typeDropdown(ApexColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius_sm),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MovementReferenceType?>(
          value: _typeFilter,
          hint: const Text('All types', style: TextStyle(fontSize: 13)),
          isDense: true,
          borderRadius: BorderRadius.circular(ApexRadius_md),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('All types', style: TextStyle(fontSize: 13)),
            ),
            ...MovementReferenceType.values.map(
              (t) => DropdownMenuItem(
                value: t,
                child: Text(
                  _typeLabel(t),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
          onChanged: (v) => setState(() => _typeFilter = v),
        ),
      ),
    );
  }

  Widget _mobileList(
    List<StockMovement> items,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        ApexSpacing.md,
        0,
        ApexSpacing.md,
        ApexSpacing.xl,
      ),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: ApexSpacing.sm),
      itemBuilder: (context, i) {
        final m = items[i];
        final isIn = m.direction == MovementDirection.in_;
        final tone = isIn ? colors.success : colors.danger;
        final direction = isIn ? 'Stock in' : 'Stock out';

        return ApexCard(
          padding: const EdgeInsets.all(ApexSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(ApexRadius_sm),
                    ),
                    child: Semantics(
                      label: direction,
                      child: Icon(
                        isIn
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded,
                        size: 18,
                        color: tone,
                      ),
                    ),
                  ),
                  const SizedBox(width: ApexSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        if (m.warehouseName?.isNotEmpty ?? false) ...[
                          const SizedBox(height: ApexSpacing.xs),
                          Text(
                            m.warehouseName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: ApexSpacing.sm),
                  StatusBadge(
                    label: _typeLabel(m.referenceType),
                    tone: StatusTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: ApexSpacing.lg),
              Row(
                children: [
                  _mobileStat(
                    context,
                    label: 'Date',
                    value: _date(m.createdAt),
                    colors: colors,
                  ),
                  _mobileStat(
                    context,
                    label: 'Quantity',
                    value: '${isIn ? '+' : ''}${fmt.quantity(m.quantity)}',
                    colors: colors,
                    valueColor: tone,
                    emphasize: true,
                  ),
                  _mobileStat(
                    context,
                    label: 'Balance',
                    value: fmt.quantity(m.balanceQuantity),
                    colors: colors,
                    alignEnd: true,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _mobileStat(
    BuildContext context, {
    required String label,
    required String value,
    required ApexColors colors,
    Color? valueColor,
    bool emphasize = false,
    bool alignEnd = false,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: ApexSpacing.xs),
          Text(
            value,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: valueColor ?? colors.textPrimary,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(
    List<StockMovement> items,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return Container(
      margin: EdgeInsets.fromLTRB(
        isMobile ? 12 : 24,
        0,
        isMobile ? 12 : 24,
        20,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius_lg),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: colors.surfaceMuted,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(flex: 16, child: Text('DATE', style: _th(colors))),
                Expanded(flex: 30, child: Text('PRODUCT', style: _th(colors))),
                Expanded(flex: 16, child: Text('SOURCE', style: _th(colors))),
                Expanded(
                  flex: 12,
                  child: Text(
                    'DIR',
                    textAlign: TextAlign.center,
                    style: _th(colors),
                  ),
                ),
                Expanded(
                  flex: 12,
                  child: Text(
                    'QTY',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
                Expanded(
                  flex: 14,
                  child: Text(
                    'BALANCE',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final m = items[i];
                final isIn = m.direction == MovementDirection.in_;
                return Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.border)),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 16,
                        child: Text(
                          _date(m.createdAt),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 30,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.productName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            if (m.warehouseName?.isNotEmpty ?? false)
                              Text(
                                m.warehouseName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 16,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: StatusBadge(
                            label: _typeLabel(m.referenceType),
                            tone: StatusTone.neutral,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 12,
                        child: Center(
                          child: Icon(
                            isIn
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            size: 16,
                            color: isIn ? colors.success : colors.danger,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 12,
                        child: Text(
                          '${isIn ? '+' : ''}${fmt.quantity(m.quantity)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isIn ? colors.success : colors.danger,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 14,
                        child: Text(
                          fmt.quantity(m.balanceQuantity),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _date(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }

  TextStyle _th(ApexColors colors) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: colors.textMuted,
  );
}
