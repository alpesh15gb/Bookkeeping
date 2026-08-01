/// Bank reconciliation detail/matching screen.
///
/// Side-by-side layout:
///   Left: bank statement transactions with suggested matches
///   Right: entry being matched with details
///   Bottom: progress bar + summary + action buttons
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import '../models/reconciliation_models.dart';
import 'reconciliation_detail_notifier.dart';

class ReconciliationDetailScreen extends ConsumerStatefulWidget {
  const ReconciliationDetailScreen({super.key, required this.reconciliationId});

  final String reconciliationId;

  @override
  ConsumerState<ReconciliationDetailScreen> createState() =>
      _ReconciliationDetailScreenState();
}

class _ReconciliationDetailScreenState
    extends ConsumerState<ReconciliationDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      reconciliationDetailProvider(widget.reconciliationId),
    );
    final notifier = ref.read(
      reconciliationDetailProvider(widget.reconciliationId).notifier,
    );
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      appBar: AppBar(
        backgroundColor: colors.surfaceRaised,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          state.reconciliation?.bankingProfileName ?? 'Bank Reconciliation',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: colors.textPrimary,
          ),
        ),
        actions: [
          if (state.hasPendingChanges)
            TextButton.icon(
              onPressed: notifier.clearAllPending,
              icon: const Icon(Icons.clear_rounded, size: 18),
              label: const Text('Clear pending'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => notifier.load(widget.reconciliationId),
          ),
        ],
      ),
      body: state.loading
          ? const Center(child: LoadingSpinner(size: 32))
          : state.error != null && state.reconciliation == null
          ? ErrorView(
              message: state.error!,
              onRetry: () => notifier.load(widget.reconciliationId),
            )
          : state.reconciliation == null
          ? const EmptyState(
              icon: Icons.account_balance_rounded,
              title: 'Reconciliation not found',
            )
          : _buildContent(state, notifier, colors, fmt, isMobile),
    );
  }

  Widget _buildContent(
    ReconciliationDetailState state,
    ReconciliationDetailNotifier notifier,
    ApexColors colors,
    NumberFormatter fmt,
    bool isMobile,
  ) {
    final stats = state.stats;

    return Column(
      children: [
        // Progress + summary bar
        _ProgressBar(stats: stats, colors: colors, fmt: fmt),
        // Success/error messages
        if (state.successMessage != null)
          _MessageBanner(
            message: state.successMessage!,
            colors: colors,
            type: 'success',
          ),
        if (state.error != null)
          _MessageBanner(message: state.error!, colors: colors, type: 'error'),
        // Main content
        Expanded(
          child: isMobile
              ? _MobileView(
                  state: state,
                  notifier: notifier,
                  colors: colors,
                  fmt: fmt,
                )
              : _DesktopView(
                  state: state,
                  notifier: notifier,
                  colors: colors,
                  fmt: fmt,
                ),
        ),
        // Bottom action bar
        _BottomBar(
          stats: stats,
          hasPending: state.hasPendingChanges,
          saving: state.saving,
          colors: colors,
          onCommit: () => notifier.commitMatches(),
          onFinalize: () => notifier.finalize(),
        ),
      ],
    );
  }
}

// ── Progress Bar ────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.stats,
    required this.colors,
    required this.fmt,
  });

  final ReconciliationStats stats;
  final ApexColors colors;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final pct = (stats.progress * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Stats
                Text(
                  '${stats.matchedTransactions}/${stats.totalTransactions} matched',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                _statChip(colors, 'Credits', fmt.currency(stats.totalCredits)),
                const SizedBox(width: 8),
                _statChip(colors, 'Debits', fmt.currency(stats.totalDebits)),
                const Spacer(),
                // Difference
                Text(
                  stats.isBalanced
                      ? 'Balanced ✓'
                      : 'Diff: ${fmt.currency(stats.difference)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: stats.isBalanced ? colors.success : colors.danger,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Progress bar
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct / 100),
            duration: const Duration(milliseconds: 400),
            builder: (context, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                backgroundColor: colors.surfaceMuted,
                valueColor: AlwaysStoppedAnimation(
                  pct == 100 ? colors.success : colors.primary,
                ),
                minHeight: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(ApexColors colors, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(ApexRadius.pill),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(fontSize: 11, color: colors.textMuted),
      ),
    );
  }
}

// ── Desktop Side-by-Side View ───────────────────────────────────────────────

class _DesktopView extends StatelessWidget {
  const _DesktopView({
    required this.state,
    required this.notifier,
    required this.colors,
    required this.fmt,
  });

  final ReconciliationDetailState state;
  final ReconciliationDetailNotifier notifier;
  final ApexColors colors;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: transaction list
        Expanded(
          flex: 5,
          child: _TransactionList(
            state: state,
            notifier: notifier,
            colors: colors,
            fmt: fmt,
          ),
        ),
        const VerticalDivider(width: 1),
        // Right: selected transaction detail + suggestions
        Expanded(
          flex: 4,
          child: _TransactionDetail(
            state: state,
            notifier: notifier,
            colors: colors,
            fmt: fmt,
          ),
        ),
      ],
    );
  }
}

// ── Mobile Single-Column View ───────────────────────────────────────────────

class _MobileView extends StatelessWidget {
  const _MobileView({
    required this.state,
    required this.notifier,
    required this.colors,
    required this.fmt,
  });

  final ReconciliationDetailState state;
  final ReconciliationDetailNotifier notifier;
  final ApexColors colors;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedTransactionId != null
        ? state.reconciliation?.transactions
              .where((t) => t.id == state.selectedTransactionId)
              .firstOrNull
        : null;

    if (selected != null) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: colors.surface,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  onPressed: () => notifier.selectTransaction(null),
                ),
                const SizedBox(width: 8),
                Text(
                  'Transaction Detail',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _TransactionDetailContent(
              transaction: selected,
              state: state,
              notifier: notifier,
              colors: colors,
              fmt: fmt,
            ),
          ),
        ],
      );
    }

    return _TransactionList(
      state: state,
      notifier: notifier,
      colors: colors,
      fmt: fmt,
    );
  }
}

// ── Transaction List ─────────────────────────────────────────────────────────

class _TransactionList extends StatelessWidget {
  const _TransactionList({
    required this.state,
    required this.notifier,
    required this.colors,
    required this.fmt,
  });

  final ReconciliationDetailState state;
  final ReconciliationDetailNotifier notifier;
  final ApexColors colors;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final transactions = state.reconciliation?.transactions ?? [];
    final isMobile = ResponsiveLayout.isMobile(context);

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: colors.surfaceMuted,
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('DATE', style: _th(colors))),
              Expanded(flex: 5, child: Text('DESCRIPTION', style: _th(colors))),
              Expanded(
                flex: 3,
                child: Text(
                  'AMOUNT',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'STATUS',
                  textAlign: TextAlign.center,
                  style: _th(colors),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: transactions.length,
            itemBuilder: (context, i) {
              final txn = transactions[i];
              final pending = state.pendingMatches[txn.id];
              final isSelected = state.selectedTransactionId == txn.id;
              final isMatched = pending?.action == MatchAction.match;
              final isExcluded = pending?.action == MatchAction.exclude;
              final suggestion = state.suggestions
                  .where((s) => s.transactionId == txn.id)
                  .firstOrNull;

              // Determine match color
              Color? matchColor;
              if (isMatched) {
                matchColor = colors.success;
              } else if (isExcluded) {
                matchColor = colors.textMuted;
              } else if (suggestion?.suggestedMatches.isNotEmpty ?? false) {
                matchColor = colors.warning;
              }

              return Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.primary.withValues(alpha: 0.06)
                      : null,
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: InkWell(
                  onTap: () =>
                      notifier.selectTransaction(isSelected ? null : txn.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // Match status indicator
                        Container(
                          width: 4,
                          height: 32,
                          decoration: BoxDecoration(
                            color: matchColor ?? Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: Text(
                            txn.transactionDate,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: Text(
                            txn.description.isEmpty
                                ? (txn.referenceNumber.isNotEmpty
                                      ? txn.referenceNumber
                                      : 'No description')
                                : txn.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            txn.creditAmount > 0
                                ? fmt.currency(txn.creditAmount)
                                : fmt.currency(txn.debitAmount),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: txn.creditAmount > 0
                                  ? colors.success
                                  : colors.textPrimary,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Center(
                            child: _StatusIndicator(
                              isMatched: isMatched,
                              isExcluded: isExcluded,
                              confidence: suggestion,
                            ),
                          ),
                        ),
                        if (isMobile)
                          const Icon(Icons.chevron_right_rounded, size: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
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

// ── Transaction Detail Panel ─────────────────────────────────────────────────

class _TransactionDetail extends StatelessWidget {
  const _TransactionDetail({
    required this.state,
    required this.notifier,
    required this.colors,
    required this.fmt,
  });

  final ReconciliationDetailState state;
  final ReconciliationDetailNotifier notifier;
  final ApexColors colors;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final selectedId = state.selectedTransactionId;
    final txn = selectedId != null
        ? state.reconciliation?.transactions
              .where((t) => t.id == selectedId)
              .firstOrNull
        : null;

    if (txn == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.touch_app_rounded,
              size: 40,
              color: colors.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Select a transaction',
              style: TextStyle(color: colors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'to view details and match',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return _TransactionDetailContent(
      transaction: txn,
      state: state,
      notifier: notifier,
      colors: colors,
      fmt: fmt,
    );
  }
}

class _TransactionDetailContent extends StatelessWidget {
  const _TransactionDetailContent({
    required this.transaction,
    required this.state,
    required this.notifier,
    required this.colors,
    required this.fmt,
  });

  final BankTransaction transaction;
  final ReconciliationDetailState state;
  final ReconciliationDetailNotifier notifier;
  final ApexColors colors;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final pending = state.pendingMatches[transaction.id];
    final isMatched = pending?.action == MatchAction.match;
    final suggestions = state.suggestions
        .where((s) => s.transactionId == transaction.id)
        .firstOrNull;
    final isMobile = ResponsiveLayout.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Transaction info card
          _Panel(
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: transaction.creditAmount > 0
                            ? colors.success.withValues(alpha: 0.1)
                            : colors.surfaceMuted,
                        borderRadius: BorderRadius.circular(ApexRadius.sm),
                      ),
                      child: Text(
                        transaction.creditAmount > 0 ? 'CREDIT' : 'DEBIT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: transaction.creditAmount > 0
                              ? colors.success
                              : colors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (isMatched)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(ApexRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 12,
                              color: colors.success,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Matched',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Amount',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                MonetaryText(
                  value: fmt.currency(
                    transaction.creditAmount > 0
                        ? transaction.creditAmount
                        : transaction.debitAmount,
                  ),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: transaction.creditAmount > 0
                      ? colors.success
                      : colors.textPrimary,
                ),
                const SizedBox(height: 12),
                _detailRow('Date', transaction.transactionDate, colors),
                if (transaction.description.isNotEmpty)
                  _detailRow('Description', transaction.description, colors),
                if (transaction.referenceNumber.isNotEmpty)
                  _detailRow('Reference', transaction.referenceNumber, colors),
                if (transaction.balance != 0)
                  _detailRow(
                    'Running Balance',
                    fmt.currency(transaction.balance),
                    colors,
                  ),
                if (pending?.notes != null)
                  _detailRow('Notes', pending!.notes!, colors),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Suggested matches
          if (suggestions != null &&
              suggestions.suggestedMatches.isNotEmpty) ...[
            Text(
              'SUGGESTED MATCHES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            ...suggestions.suggestedMatches.map(
              (match) => _SuggestionCard(
                match: match,
                isSelected: pending?.suggestedMatch?.id == match.id,
                colors: colors,
                fmt: fmt,
                onTap: () => notifier.applySuggestion(transaction.id, match),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Action buttons
          if (!isMatched) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: suggestions?.suggestedMatches.isNotEmpty ?? false
                        ? () => notifier.applySuggestion(
                            transaction.id,
                            suggestions!.suggestedMatches.first,
                          )
                        : null,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Match'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        notifier.excludeTransaction(transaction.id),
                    icon: const Icon(Icons.not_interested_rounded, size: 16),
                    label: const Text('Exclude'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                // Categorize: create a new ledger entry
                notifier.categorizeTransaction(transaction.id);
              },
              icon: const Icon(Icons.category_rounded, size: 16),
              label: const Text('Categorize as new entry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textSecondary,
              ),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: () => notifier.unmatchTransaction(transaction.id),
              icon: const Icon(Icons.undo_rounded, size: 16),
              label: const Text('Undo match'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.danger,
                side: BorderSide(color: colors.danger.withValues(alpha: 0.4)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, ApexColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            '$label  ',
            style: TextStyle(
              fontSize: 11,
              color: colors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Suggestion Card ──────────────────────────────────────────────────────────

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.match,
    required this.isSelected,
    required this.colors,
    required this.fmt,
    required this.onTap,
  });

  final SuggestedMatch match;
  final bool isSelected;
  final ApexColors colors;
  final NumberFormatter fmt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final confidenceColor = match.score >= 90
        ? colors.success
        : match.score >= 70
        ? colors.info
        : match.score >= 50
        ? colors.warning
        : colors.textMuted;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? colors.primary.withValues(alpha: 0.06)
            : colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.md),
        border: Border.all(
          color: isSelected ? colors.primary : colors.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ApexRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Confidence badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: confidenceColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ApexRadius.sm),
                ),
                child: Center(
                  child: Text(
                    '${match.score}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: confidenceColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      match.reference ?? 'System entry',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${match.date}  ·  ${fmt.currency(double.tryParse(match.amount) ?? 0)}',
                      style: TextStyle(fontSize: 11, color: colors.textMuted),
                    ),
                    if (match.contactName != null &&
                        match.contactName!.isNotEmpty)
                      Text(
                        match.contactName!,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              // Confidence label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: confidenceColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(ApexRadius.pill),
                ),
                child: Text(
                  match.confidenceLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: confidenceColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status Indicator ─────────────────────────────────────────────────────────

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({
    required this.isMatched,
    required this.isExcluded,
    this.confidence,
  });

  final bool isMatched;
  final bool isExcluded;
  final MatchSuggestion? confidence;

  @override
  Widget build(BuildContext context) {
    if (isMatched) {
      return const Icon(
        Icons.check_circle_rounded,
        size: 18,
        color: Colors.green,
      );
    }
    if (isExcluded) {
      return Icon(
        Icons.not_interested_rounded,
        size: 16,
        color: Colors.grey[400],
      );
    }
    if (confidence != null && confidence!.suggestedMatches.isNotEmpty) {
      final topScore = confidence!.suggestedMatches.first.score;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: topScore >= 70
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '$topScore%',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: topScore >= 70 ? Colors.green : Colors.orange,
          ),
        ),
      );
    }
    return Icon(Icons.circle_rounded, size: 8, color: Colors.grey[400]);
  }
}

// ── Bottom Action Bar ────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.stats,
    required this.hasPending,
    required this.saving,
    required this.colors,
    required this.onCommit,
    required this.onFinalize,
  });

  final ReconciliationStats stats;
  final bool hasPending;
  final bool saving;
  final ApexColors colors;
  final VoidCallback onCommit;
  final VoidCallback onFinalize;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(top: BorderSide(color: colors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveLayout.isMobile(context) ? 12 : 20,
        vertical: 12,
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${stats.matchedTransactions}/${stats.totalTransactions} matched',
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(ApexRadius.pill),
            ),
            child: Text(
              '${(stats.progress * 100).round()}%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: hasPending ? onCommit : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textSecondary,
            ),
            child: Text(saving ? 'Saving…' : 'Save matches'),
          ),
          FilledButton.icon(
            onPressed: saving ? null : onFinalize,
            icon: saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: Text(
              stats.pendingTransactions == 0
                  ? 'Complete reconciliation'
                  : 'Save & continue',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Message Banner ───────────────────────────────────────────────────────────

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    required this.message,
    required this.colors,
    required this.type,
  });

  final String message;
  final ApexColors colors;
  final String type;

  @override
  Widget build(BuildContext context) {
    final isSuccess = type == 'success';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: (isSuccess ? colors.success : colors.danger).withValues(
        alpha: 0.1,
      ),
      child: Row(
        children: [
          Icon(
            isSuccess
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            size: 18,
            color: isSuccess ? colors.success : colors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isSuccess ? colors.success : colors.danger,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared Panel ─────────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  const _Panel({required this.colors, required this.child});
  final ApexColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}
