/// Issue confirmation screen.
///
/// Shows the invoice summary, allocation status, and a confirm button.
/// The UI never performs business logic — it calls [InvoiceRepository.issue]
/// which owns validation, numbering, freeze, journal, and outbox.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../notifiers/invoice_form_notifier.dart';
import '../notifiers/invoice_issue_notifier.dart';

class InvoiceIssueScreen extends ConsumerStatefulWidget {
  const InvoiceIssueScreen({super.key, required this.draftLocalId});
  final String draftLocalId;

  @override
  ConsumerState<InvoiceIssueScreen> createState() => _InvoiceIssueScreenState();
}

class _InvoiceIssueScreenState extends ConsumerState<InvoiceIssueScreen> {
  @override
  void initState() {
    super.initState();
    // Trigger allocation check on load.
    Future.microtask(() => _checkAllocation(ref));
  }

  Future<void> _checkAllocation(WidgetRef ref) async {
    await ref
        .read(invoiceIssueProvider.notifier)
        .checkAllocation(companyId: '', deviceId: '', financialYearId: '');
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(invoiceFormProvider);
    final issueState = ref.watch(invoiceIssueProvider);
    final colors = apexColors(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Issue')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Customer ──────────────────────────────────────────────────
            _section('Customer', formState.customerName, Icons.person_rounded),

            const SizedBox(height: 16),

            // ── Number preview ────────────────────────────────────────────
            _section(
              'Invoice number',
              issueState.allocation != null
                  ? issueState.allocation!.nextDisplayNumber
                  : '—',
              Icons.tag_rounded,
            ),

            const SizedBox(height: 16),

            // ── Date ──────────────────────────────────────────────────────
            _section(
              'Date',
              formState.invoiceDate,
              Icons.calendar_today_rounded,
            ),

            const SizedBox(height: 16),

            // ── Totals ────────────────────────────────────────────────────
            _totalsSection(formState, colors),

            const SizedBox(height: 16),

            // ── Allocation warning ────────────────────────────────────────
            if (issueState.isBlocked)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colors.danger.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: colors.danger,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        issueState.error ?? 'Cannot issue invoice.',
                        style: TextStyle(color: colors.danger, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // ── Error ─────────────────────────────────────────────────────
            if (issueState.error != null && !issueState.isBlocked)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  issueState.error!,
                  style: TextStyle(color: colors.danger, fontSize: 13),
                ),
              ),

            const SizedBox(height: 24),

            // ── Confirm ───────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: issueState.canIssue && !issueState.isIssuing
                    ? () => _confirm()
                    : null,
                icon: issueState.isIssuing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_rounded),
                label: Text(
                  issueState.isIssuing ? 'Issuing…' : 'Issue Invoice',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    final entity = await ref
        .read(invoiceIssueProvider.notifier)
        .issue(
          localId: widget.draftLocalId,
          companyId: '',
          deviceId: '',
          financialYearId: '',
        );
    if (entity != null && mounted) {
      // Pop with the issued entity so the caller knows issue succeeded.
      Navigator.of(context).pop(entity);
    }
  }

  Widget _section(String label, String value, IconData icon) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
    );
  }

  Widget _totalsSection(InvoiceFormState state, ApexColors colors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'Invoice totals',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const Divider(),
            _row(
              'Subtotal',
              Money.fromPaise(state.totalBeforeTaxPaise),
              colors,
            ),
            if (state.discountPaise > 0)
              _row('Discount', Money.fromPaise(-state.discountPaise), colors),
            _row('GST', Money.fromPaise(state.taxPaise), colors),
            const Divider(height: 8),
            _row(
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

  Widget _row(
    String label,
    Money amount,
    ApexColors colors, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              color: colors.textSecondary,
            ),
          ),
          Text(
            '₹${amount.toRupees().toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 18 : 14,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
