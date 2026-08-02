import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/sync/journal_lifecycle_status.dart';
import 'package:apexbooks/core/sync/sync_status.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/search_bar.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/features/journals/domain/commands/journal_commands.dart';
import 'package:apexbooks/features/journals/domain/entities/journal_entity.dart';
import 'package:apexbooks/features/journals/presentation/providers/journal_providers.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import 'journal_form_screen.dart';

class JournalListScreen extends ConsumerStatefulWidget {
  const JournalListScreen({super.key});

  @override
  ConsumerState<JournalListScreen> createState() => _JournalListScreenState();
}

class _JournalListScreenState extends ConsumerState<JournalListScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _post(JournalEntryEntity entry) async {
    try {
      await ref
          .read(journalRepositoryProvider)
          .postJournal(
            PostJournalCommand(
              localId: entry.localId,
              companyId: entry.companyId,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Journal posted locally; sync is pending.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _editDraft(JournalEntryEntity entry) async {
    if (!entry.isDraft) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => JournalFormScreen(entry: entry)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _reverse(JournalEntryEntity entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reverse journal?'),
        content: const Text(
          'Posted journals are corrected by reversal. This creates a new journal with the debit and credit lines flipped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reverse'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final today = DateTime.now();
    final reversalDate =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    try {
      await ref
          .read(journalRepositoryProvider)
          .reverseJournal(
            ReverseJournalCommand(
              localId: entry.localId,
              companyId: entry.companyId,
              reversalDate: reversalDate,
              description:
                  'Reversal of ${entry.referenceNumber ?? entry.description}',
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reversal journal created locally.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _retry(JournalEntryEntity entry) async {
    await ref.read(journalRepositoryProvider).retrySync(entry.localId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Journal queued for sync retry.')),
    );
  }

  Future<void> _resolveConflict(JournalEntryEntity entry) async {
    await ref.read(journalRepositoryProvider).resolveConflict(entry.localId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Conflict resolved using the server version.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncVals = ref.watch(journalsStreamProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Journal Entries',
            subtitle:
                'Double-entry postings from invoices, bills, and manual journals.',
            actions: [
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const JournalFormScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('New journal'),
              ),
            ],
          ),
          Expanded(
            child: asyncVals.when(
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
                onRetry: () => ref.invalidate(journalsStreamProvider),
              ),
              data: (items) {
                final q = _search.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? items
                    : items
                          .where(
                            (e) =>
                                e.description.toLowerCase().contains(q) ||
                                (e.referenceNumber ?? '')
                                    .toLowerCase()
                                    .contains(q) ||
                                e.sourceType.toLowerCase().contains(q) ||
                                e.lifecycleStatus.name.contains(q) ||
                                e.syncStatus.label.toLowerCase().contains(q) ||
                                e.lines.any(
                                  (l) =>
                                      l.accountName.toLowerCase().contains(q) ||
                                      l.accountCode.toLowerCase().contains(q),
                                ),
                          )
                          .toList();
                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isMobile ? ApexSpacing.md : ApexSpacing.xl,
                        0,
                        isMobile ? ApexSpacing.md : ApexSpacing.xl,
                        ApexSpacing.sm,
                      ),
                      child: ApexSearchBar(
                        controller: _searchCtrl,
                        hintText: 'Search by account, description, reference…',
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                    Expanded(
                      child: items.isEmpty
                          ? const EmptyState(
                              icon: Icons.book_outlined,
                              title: 'No journals found',
                              subtitle:
                                  'Create a manual journal; it saves locally and syncs when online.',
                            )
                          : filtered.isEmpty
                          ? const EmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'No matches',
                              subtitle: 'Try a different search term.',
                            )
                          : ListView.builder(
                              padding: EdgeInsets.fromLTRB(
                                isMobile ? ApexSpacing.md : ApexSpacing.xl,
                                0,
                                isMobile ? ApexSpacing.md : ApexSpacing.xl,
                                ApexSpacing.lg,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, idx) => _entryCard(
                                filtered[idx],
                                colors,
                                fmt,
                                isMobile: isMobile,
                              ),
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

  Widget _entryCard(
    JournalEntryEntity entry,
    ApexColors colors,
    NumberFormatter fmt, {
    required bool isMobile,
  }) {
    final title = entry.description.isEmpty
        ? ((entry.referenceNumber ?? '').isEmpty
              ? 'Journal entry'
              : entry.referenceNumber!)
        : entry.description;
    final date = entry.entryDate.isEmpty ? '—' : entry.entryDate;

    return Semantics(
      container: true,
      label:
          'Journal entry $title dated $date, ${entry.lifecycleStatus.name}, ${entry.syncStatus.label}',
      child: Container(
        margin: const EdgeInsets.only(bottom: ApexSpacing.md),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(ApexRadius_lg),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(ApexRadius_lg),
                ),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? ApexSpacing.md : ApexSpacing.lg,
                vertical: ApexSpacing.sm,
              ),
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: ApexSpacing.xs),
                        Text(
                          date,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: ApexSpacing.sm),
                        Wrap(
                          spacing: ApexSpacing.xs,
                          runSpacing: ApexSpacing.xs,
                          children: _badges(entry),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Text(
                          date,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
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
                        ..._badges(
                          entry,
                        ).expand((badge) => [badge, const SizedBox(width: 6)]),
                      ],
                    ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? ApexSpacing.md : ApexSpacing.lg,
                vertical: ApexSpacing.sm,
              ),
              child: Column(
                children: [
                  if (!isMobile) ...[
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
                  ],
                  ...entry.lines.map(
                    (line) => isMobile
                        ? _mobileLineTile(line, colors, fmt)
                        : _desktopLineRow(line, colors, fmt),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: ApexSpacing.xs,
                    ),
                    child: Divider(height: 1, color: colors.border),
                  ),
                  isMobile
                      ? Column(
                          children: [
                            _amountSummaryRow(
                              'Debit total',
                              fmt.currency(entry.totalDebit.toRupees()),
                              colors,
                            ),
                            const SizedBox(height: ApexSpacing.xs),
                            _amountSummaryRow(
                              'Credit total',
                              fmt.currency(entry.totalCredit.toRupees()),
                              colors,
                            ),
                          ],
                        )
                      : Row(
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
                                fmt.currency(entry.totalDebit.toRupees()),
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
                                fmt.currency(entry.totalCredit.toRupees()),
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
                  const SizedBox(height: ApexSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: ApexSpacing.sm,
                      runSpacing: ApexSpacing.sm,
                      children: [
                        if (entry.isDraft)
                          OutlinedButton.icon(
                            onPressed: () => _editDraft(entry),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit draft'),
                          ),
                        if (entry.isDraft)
                          OutlinedButton.icon(
                            onPressed: () => _post(entry),
                            icon: const Icon(
                              Icons.check_circle_outline_rounded,
                            ),
                            label: const Text('Post'),
                          ),
                        if (entry.isPosted)
                          OutlinedButton.icon(
                            onPressed: () => _reverse(entry),
                            icon: const Icon(Icons.undo_rounded),
                            label: const Text('Reverse'),
                          ),
                        if (entry.hasSyncIssue)
                          OutlinedButton.icon(
                            onPressed: entry.syncStatus == SyncStatus.conflict
                                ? () => _resolveConflict(entry)
                                : () => _retry(entry),
                            icon: const Icon(Icons.sync_problem_rounded),
                            label: Text(
                              entry.syncStatus == SyncStatus.conflict
                                  ? 'Resolve conflict'
                                  : 'Retry sync',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _badges(JournalEntryEntity entry) => [
    StatusBadge(label: entry.sourceType, tone: StatusTone.neutral),
    StatusBadge(
      label: entry.lifecycleStatus.name.toUpperCase(),
      tone: _lifecycleTone(entry.lifecycleStatus),
    ),
    StatusBadge(
      label: entry.syncStatus.label.toUpperCase(),
      tone: _syncTone(entry.syncStatus),
    ),
    StatusBadge(
      label: entry.isBalanced ? 'BALANCED' : 'UNBALANCED',
      tone: entry.isBalanced ? StatusTone.success : StatusTone.danger,
    ),
  ];

  StatusTone _lifecycleTone(JournalLifecycleStatus status) => switch (status) {
    JournalLifecycleStatus.draft => StatusTone.warning,
    JournalLifecycleStatus.posted => StatusTone.success,
    JournalLifecycleStatus.reversed => StatusTone.info,
  };

  StatusTone _syncTone(SyncStatus status) => switch (status) {
    SyncStatus.localOnly || SyncStatus.pending => StatusTone.warning,
    SyncStatus.syncing => StatusTone.info,
    SyncStatus.synced => StatusTone.success,
    SyncStatus.failed || SyncStatus.conflict => StatusTone.danger,
  };

  Widget _desktopLineRow(
    JournalLineEntity line,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ApexSpacing.xs),
      child: Row(
        children: [
          Expanded(
            flex: 50,
            child: Row(
              children: [
                if (line.accountCode.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      line.accountCode,
                      style: TextStyle(fontSize: 11, color: colors.textMuted),
                    ),
                  ),
                Expanded(
                  child: Text(
                    line.accountName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 25,
            child: Text(
              line.direction.isDebit
                  ? fmt.currency(line.amount.toRupees())
                  : '',
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
              line.direction.isCredit
                  ? fmt.currency(line.amount.toRupees())
                  : '',
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
  }

  Widget _mobileLineTile(
    JournalLineEntity line,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: ApexSpacing.sm),
      padding: const EdgeInsets.all(ApexSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(ApexRadius_md),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.accountName.isEmpty
                ? 'Account not selected'
                : line.accountName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          if (line.accountCode.isNotEmpty) ...[
            const SizedBox(height: ApexSpacing.xs),
            Text(
              line.accountCode,
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
          ],
          const SizedBox(height: ApexSpacing.sm),
          _amountSummaryRow(
            line.direction.isDebit ? 'Debit' : 'Credit',
            fmt.currency(line.amount.toRupees()),
            colors,
          ),
        ],
      ),
    );
  }

  Widget _amountSummaryRow(String label, String value, ApexColors colors) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }

  TextStyle _th(ApexColors colors) => TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: colors.textMuted,
  );
}
