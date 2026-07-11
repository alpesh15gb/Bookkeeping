import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/features/inventory/stock/models/stock_models.dart';
import 'stock_movement_list_provider.dart';

class StockMovementListScreen extends ConsumerStatefulWidget {
  const StockMovementListScreen({super.key});
  @override
  ConsumerState<StockMovementListScreen> createState() =>
      _StockMovementListScreenState();
}

class _StockMovementListScreenState
    extends ConsumerState<StockMovementListScreen> {
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
          Padding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 12 : 24, 0, isMobile ? 12 : 24, 10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search product…',
                      isDense: true,
                      filled: true,
                      fillColor: colors.surfaceRaised,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      contentPadding: EdgeInsets.symmetric(
                        vertical: isMobile ? 14 : 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ApexRadius.sm),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ApexRadius.sm),
                        borderSide: BorderSide(color: colors.border),
                      ),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(width: 12),
                _typeDropdown(colors),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: LoadingSpinner(size: 36)),
              error: (err, _) => ErrorView(
                message: err.toString(),
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
                return _table(filtered, colors, fmt);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeDropdown(ApexColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.sm),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MovementReferenceType?>(
          value: _typeFilter,
          hint: const Text('All types', style: TextStyle(fontSize: 13)),
          isDense: true,
          borderRadius: BorderRadius.circular(ApexRadius.md),
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

  Widget _table(
    List<StockMovement> items,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return Container(
      margin: EdgeInsets.fromLTRB(
        isMobile ? 12 : 24, 0, isMobile ? 12 : 24, 20,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
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
                        child: Text(
                          m.productName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
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
