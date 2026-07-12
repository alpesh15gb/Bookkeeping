import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/search_bar.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/journal_entry.dart';
import '../services/journal_service.dart';

final journalsListProvider = FutureProvider.autoDispose<List<JournalEntry>>((
  ref,
) async {
  final res = await ref.watch(journalServiceProvider).list();
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

class JournalListScreen extends ConsumerStatefulWidget {
  const JournalListScreen({super.key});
  @override
  ConsumerState<JournalListScreen> createState() => _JournalListScreenState();
}

class _JournalListScreenState extends ConsumerState<JournalListScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final asyncVals = ref.watch(journalsListProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          const PageHeader(
            title: 'Journal Entries',
            subtitle:
                'Double-entry postings from invoices, bills, and manual journals.',
          ),
          Expanded(
            child: asyncVals.when(
              loading: () => const Center(child: LoadingSpinner(size: 36)),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(journalsListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.book_outlined,
                    title: 'No journals found',
                    subtitle:
                        'Double-entry postings automatically generate from invoices/bills.',
                  );
                }
                final q = _search.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? items
                    : items
                          .where(
                            (e) =>
                                e.description.toLowerCase().contains(q) ||
                                e.referenceNumber.toLowerCase().contains(q) ||
                                e.sourceType.toLowerCase().contains(q) ||
                                e.lines.any(
                                  (l) =>
                                      l.accountName.toLowerCase().contains(q),
                                ),
                          )
                          .toList();
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(ApexSpacing.xl, 0, ApexSpacing.xl, ApexSpacing.sm),
                      child: ApexSearchBar(
                        controller: _searchCtrl,
                        hintText: 'Search by account, description, reference…',
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const EmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'No matches',
                              subtitle: 'Try a different search term.',
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(ApexSpacing.xl, 0, ApexSpacing.xl, ApexSpacing.lg),
                              itemCount: filtered.length,
                              itemBuilder: (context, idx) =>
                                  _entryCard(filtered[idx], colors, fmt),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryCard(JournalEntry e, ApexColors colors, NumberFormatter fmt) {
    return Container(
      margin: const EdgeInsets.only(bottom: ApexSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(ApexRadius.lg),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: ApexSpacing.lg, vertical: ApexSpacing.sm),
            child: Row(
              children: [
                Text(
                  e.entryDate.isEmpty ? '—' : e.entryDate,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    e.description.isEmpty
                        ? (e.referenceNumber.isEmpty
                              ? 'Journal entry'
                              : e.referenceNumber)
                        : e.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(label: e.sourceType, tone: StatusTone.neutral),
                const SizedBox(width: 6),
                StatusBadge(
                  label: e.isBalanced ? 'BALANCED' : 'UNBALANCED',
                  tone: e.isBalanced ? StatusTone.success : StatusTone.danger,
                ),
              ],
            ),
          ),
          // Debit | Credit columns
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ApexSpacing.lg, vertical: ApexSpacing.sm),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 50,
                      child: Text('ACCOUNT', style: _th(colors)),
                    ),
                    Expanded(
                      flex: 25,
                      child: Text(
                        'DEBIT',
                        textAlign: TextAlign.right,
                        style: _th(colors),
                      ),
                    ),
                    Expanded(
                      flex: 25,
                      child: Text(
                        'CREDIT',
                        textAlign: TextAlign.right,
                        style: _th(colors),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ...e.lines.map(
                  (l) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: ApexSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 50,
                          child: Row(
                            children: [
                              if (l.accountCode.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Text(
                                    l.accountCode,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.textMuted,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  l.accountName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 25,
                          child: Text(
                            l.direction.isDebit ? fmt.currency(l.amount) : '',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 25,
                          child: Text(
                            l.direction.isCredit ? fmt.currency(l.amount) : '',
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
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: ApexSpacing.xs),
                  child: Divider(height: 1, color: colors.border),
                ),
                Row(
                  children: [
                    Expanded(
                      flex: 50,
                      child: Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 25,
                      child: Text(
                        fmt.currency(e.totalDebit),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 25,
                      child: Text(
                        fmt.currency(e.totalCredit),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _th(ApexColors colors) => TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: colors.textMuted,
  );
}
