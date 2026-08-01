/// Invoice form screen — offline-first draft editor.
///
/// Captures user intent only.  Repository re-computes totals on save.
/// Drafts never consume a legal number.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:apexbooks/core/database/database_provider.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/utils/money.dart';
import 'package:apexbooks/core/sync/sync_status.dart';
import 'package:apexbooks/core/presentation/design_system/tokens/app_spacing.dart';
import 'package:apexbooks/features/invoices/presentation/notifiers/invoice_form_notifier.dart';
import 'package:apexbooks/features/auth/presentation/auth_controller.dart';

// ── Reactive provider for local contacts ───────────────────────────────────

final _localContactsProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final companyId =
      ref.watch(authControllerProvider).activeMembership?.tenantId ?? '';
  return (db.select(db.contacts)
        ..where(
          (c) =>
              c.companyId.equals(companyId) &
              c.isActive.equals(true) &
              (c.contactType.equals('customer') | c.contactType.equals('both')),
        )
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .watch();
});

final _localProductsProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final companyId =
      ref.watch(authControllerProvider).activeMembership?.tenantId ?? '';
  return (db.select(db.stockItems)
        ..where(
          (item) =>
              item.companyId.equals(companyId) &
              item.isActive.equals(true) &
              item.deletedAt.isNull(),
        )
        ..orderBy([(item) => OrderingTerm.asc(item.name)]))
      .watch();
});

class InvoiceFormScreen extends ConsumerStatefulWidget {
  const InvoiceFormScreen({super.key});
  @override
  ConsumerState<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends ConsumerState<InvoiceFormScreen> {
  final _searchCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(invoiceFormProvider);
    final notifier = ref.read(invoiceFormProvider.notifier);
    final colors = apexColors(context);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: state.isDraft ? 'New Invoice' : 'Invoice',
            subtitle: state.isDraft
                ? 'Create a draft invoice — no number assigned yet.'
                : 'Issued — number ${state.localId?.substring(0, 6)}',
            actions: [
              if (state.isDraft)
                FilledButton.icon(
                  onPressed: state.isValid && !state.saving
                      ? () => _saveDraft(notifier)
                      : null,
                  icon: state.saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(state.saving ? 'Saving…' : 'Save draft'),
                ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Status banner ─────────────────────────────────────
                    if (!state.isDraft && state.syncStatus != null)
                      _syncBanner(state.syncStatus!, colors),

                    // ── Header fields ─────────────────────────────────────
                    _dateField(state, notifier),
                    const SizedBox(height: AppSpacing.lg),
                    _customerField(state, notifier),
                    const SizedBox(height: AppSpacing.lg),
                    _optionalFields(state, notifier),

                    const SizedBox(height: AppSpacing.xxl),

                    // ── Lines ─────────────────────────────────────────────
                    _linesHeader(state, notifier),
                    const SizedBox(height: AppSpacing.sm),
                    ...state.lines.asMap().entries.map(
                      (e) => _lineCard(e.key, e.value, notifier, state, colors),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // ── Totals ────────────────────────────────────────────
                    _totalsCard(state, colors),
                    const SizedBox(height: AppSpacing.xxl),

                    // ── Error ─────────────────────────────────────────────
                    if (state.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: Text(
                          state.error!,
                          style: TextStyle(color: colors.danger, fontSize: 13),
                        ),
                      ),

                    // ── Last saved ────────────────────────────────────────
                    if (state.lastSaved != null)
                      Text(
                        'Saved ${state.lastSaved!.toLocal().toString().substring(0, 19)}',
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Save draft ─────────────────────────────────────────────────────────

  Future<void> _saveDraft(InvoiceFormNotifier notifier) async {
    final ok = await notifier.saveDraft();
    if (ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Draft saved.')));
    }
  }

  // ── Sync status banner ─────────────────────────────────────────────────

  Widget _syncBanner(String status, ApexColors colors) {
    final label = SyncStatus.values
        .firstWhere((s) => s.name == status, orElse: () => SyncStatus.localOnly)
        .label;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_rounded, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Text('Sync: $label'),
        ],
      ),
    );
  }

  // ── Date field ─────────────────────────────────────────────────────────

  Widget _dateField(InvoiceFormState state, InvoiceFormNotifier notifier) {
    return TextFormField(
      initialValue: state.invoiceDate,
      decoration: const InputDecoration(
        labelText: 'Invoice date',
        hintText: 'YYYY-MM-DD',
        prefixIcon: Icon(Icons.calendar_today_rounded),
      ),
      onChanged: notifier.setDate,
    );
  }

  // ── Customer field ─────────────────────────────────────────────────────

  Widget _customerField(InvoiceFormState state, InvoiceFormNotifier notifier) {
    final contacts = ref.watch(_localContactsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.customerName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.customerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => notifier.setCustomer('', ''),
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  label: const Text('Change'),
                ),
              ],
            ),
          ),
        contacts.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error loading contacts: $e'),
          data: (rows) {
            return Autocomplete<String>(
              optionsBuilder: (text) {
                if (text.text.isEmpty) return rows.map((c) => c.name);
                return rows
                    .where(
                      (c) => c.name.toLowerCase().contains(
                        text.text.toLowerCase(),
                      ),
                    )
                    .map((c) => c.name);
              },
              onSelected: (name) {
                final contact = rows.firstWhere(
                  (c) => c.name == name,
                  orElse: () => rows.first,
                );
                notifier.setCustomer(
                  contact.remoteId.isNotEmpty
                      ? contact.remoteId
                      : contact.localId,
                  contact.name,
                  gstin: contact.gstin,
                  stateCode: contact.stateCode,
                );
              },
              fieldViewBuilder: (ctx, ctrl, focus, submit) => TextField(
                controller: ctrl,
                focusNode: focus,
                decoration: const InputDecoration(
                  labelText: 'Customer',
                  hintText: 'Search contacts…',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                onSubmitted: (_) => submit(),
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Optional fields ────────────────────────────────────────────────────

  Widget _optionalFields(InvoiceFormState state, InvoiceFormNotifier notifier) {
    return Column(
      children: [
        TextFormField(
          initialValue: state.dueDate ?? '',
          decoration: const InputDecoration(
            labelText: 'Due date (optional)',
            hintText: 'YYYY-MM-DD',
            prefixIcon: Icon(Icons.event_rounded),
          ),
          onChanged: notifier.setDueDate,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          initialValue: state.referenceNumber ?? '',
          decoration: const InputDecoration(
            labelText: 'Reference / PO number',
            prefixIcon: Icon(Icons.tag_rounded),
          ),
          onChanged: notifier.setReference,
        ),
      ],
    );
  }

  // ── Lines header ───────────────────────────────────────────────────────

  Widget _linesHeader(InvoiceFormState state, InvoiceFormNotifier notifier) {
    return Row(
      children: [
        const Text(
          'Line items',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: notifier.addLine,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add line'),
        ),
      ],
    );
  }

  // ── Line card ──────────────────────────────────────────────────────────

  Widget _lineCard(
    int index,
    InvoiceFormLine line,
    InvoiceFormNotifier notifier,
    InvoiceFormState formState,
    ApexColors colors,
  ) {
    final products = ref.watch(_localProductsProvider).valueOrNull ?? const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('invoice-product-$index-${line.productId}'),
                    initialValue:
                        products.any(
                          (product) =>
                              (product.remoteId ?? product.localId) ==
                              line.productId,
                        )
                        ? line.productId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Product / service',
                      isDense: true,
                    ),
                    hint: Text(
                      products.isEmpty
                          ? 'Connect once to load products'
                          : 'Select product',
                    ),
                    items: products
                        .map(
                          (product) => DropdownMenuItem(
                            value: product.remoteId ?? product.localId,
                            child: Text(
                              product.sku?.isNotEmpty == true
                                  ? '${product.name} · ${product.sku}'
                                  : product.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: products.isEmpty
                        ? null
                        : (id) {
                            final product = products.firstWhere(
                              (candidate) =>
                                  (candidate.remoteId ?? candidate.localId) ==
                                  id,
                            );
                            notifier.updateLine(
                              index,
                              line.copyWith(
                                productId: product.remoteId ?? product.localId,
                                productName: product.name,
                                hsnSac: product.hsnSac,
                                unitPricePaise: product.salesPricePaise,
                                taxRateBasisPoints: product.gstRateBasisPoints,
                              ),
                            );
                          },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    initialValue: line.quantity,
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) =>
                        notifier.updateLine(index, line.copyWith(quantity: v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (line.productId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'HSN ${line.hsnSac ?? '—'} · GST ${(line.taxRateBasisPoints / 100).toStringAsFixed(2)}%',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: line.unitPricePaise > 0
                        ? Money.fromPaise(
                            line.unitPricePaise,
                          ).toRupees().toStringAsFixed(2)
                        : '',
                    decoration: const InputDecoration(
                      labelText: 'Unit price (₹)',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => notifier.updateLine(
                      index,
                      line.copyWith(
                        unitPricePaise: Money.fromRupees(
                          double.tryParse(v) ?? 0,
                        ).toPaise(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '₹${Money.fromPaise(line.amountPaise).toRupees().toStringAsFixed(2)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: line.discountPaise > 0
                        ? Money.fromPaise(
                            line.discountPaise,
                          ).toRupees().toStringAsFixed(2)
                        : '',
                    decoration: const InputDecoration(
                      labelText: 'Discount (₹)',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => notifier.updateLine(
                      index,
                      line.copyWith(
                        discountPaise: Money.fromRupees(
                          double.tryParse(v) ?? 0,
                        ).toPaise(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (formState.lines.length > 1)
                  IconButton(
                    onPressed: () => notifier.removeLine(index),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: colors.danger,
                    ),
                    tooltip: 'Remove line',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Totals card ────────────────────────────────────────────────────────

  Widget _totalsCard(InvoiceFormState state, ApexColors colors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _totalRow(
              'Subtotal',
              Money.fromPaise(state.totalBeforeTaxPaise),
              colors,
            ),
            if (state.discountPaise > 0)
              _totalRow(
                'Discount',
                Money.fromPaise(-state.discountPaise),
                colors,
              ),
            _totalRow('GST (18%)', Money.fromPaise(state.taxPaise), colors),
            const Divider(height: 24),
            _totalRow(
              'Total',
              Money.fromPaise(state.totalPaise),
              colors,
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(
    String label,
    Money amount,
    ApexColors colors, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 120,
            child: Text(
              '₹${amount.toRupees().toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                fontSize: bold ? 18 : 14,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
