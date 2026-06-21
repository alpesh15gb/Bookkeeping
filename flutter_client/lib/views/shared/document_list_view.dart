import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/views/shared/app_components.dart';

/// Summary statistics for the list header
class ListSummaryData {
  final double totalAmount;
  final double paidAmount;
  final double pendingAmount;
  final int totalCount;
  final int paidCount;
  final int pendingCount;

  const ListSummaryData({
    this.totalAmount = 0,
    this.paidAmount = 0,
    this.pendingAmount = 0,
    this.totalCount = 0,
    this.paidCount = 0,
    this.pendingCount = 0,
  });
}

/// Configuration for a single filter tab
class FilterTab {
  final String label;
  final int count;
  const FilterTab(this.label, this.count);
}

/// Configuration for a single document item in the list
class DocumentItemData {
  final String id;
  final String docNumber;
  final String? partyName;
  final String? date;
  final num amount;
  final String status;
  final String? balanceLabel;
  final num? balanceAmount;

  const DocumentItemData({
    required this.id,
    required this.docNumber,
    this.partyName,
    this.date,
    required this.amount,
    required this.status,
    this.balanceLabel,
    this.balanceAmount,
  });
}

/// A unified document list body widget following accounting app best practices.
///
/// Provides: search bar, filter chips with counts, summary stats,
/// pull-to-refresh list, and empty state.
///
/// This widget does NOT include its own Scaffold, AppBar, or FAB.
/// It is designed to be placed inside the shell view's body area.
class DocumentListView extends StatefulWidget {
  final String title;
  final Widget Function(BuildContext, DocumentItemData) detailBuilder;

  /// Items to display (already filtered by the caller)
  final List<DocumentItemData> items;

  /// Filter tabs with counts
  final List<FilterTab> filterTabs;

  /// Currently active filter
  final String activeFilter;

  /// Called when user taps a filter tab
  final ValueChanged<String> onFilterChanged;

  /// Summary statistics
  final ListSummaryData? summary;

  /// Search controller
  final TextEditingController searchController;

  /// Search hint text
  final String searchHint;

  /// Called when search text changes
  final ValueChanged<String> onSearchChanged;

  /// Called on pull-to-refresh
  final Future<void> Function() onRefresh;

  /// Whether data is still loading
  final bool isLoading;

  /// Empty state configuration
  final String emptyTitle;
  final String emptySubtitle;
  final IconData emptyIcon;

  /// Optional custom item builder. When provided, overrides the default
  /// [CompactDocumentCard] rendering. Useful for contacts, products, etc.
  final Widget Function(BuildContext context, DocumentItemData item, int index)? itemBuilder;

  const DocumentListView({
    super.key,
    required this.title,
    required this.detailBuilder,
    required this.items,
    required this.filterTabs,
    required this.activeFilter,
    required this.onFilterChanged,
    this.summary,
    required this.searchController,
    this.searchHint = 'Search...',
    required this.onSearchChanged,
    required this.onRefresh,
    this.isLoading = false,
    this.emptyTitle = 'No items yet',
    this.emptySubtitle = 'Tap + to create your first item',
    this.emptyIcon = Icons.receipt_long_outlined,
    this.itemBuilder,
  });

  @override
  State<DocumentListView> createState() => _DocumentListViewState();
}

class _DocumentListViewState extends State<DocumentListView> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchBar(),
        if (widget.filterTabs.isNotEmpty) _buildFilterChips(),
        if (widget.summary != null) _buildSummaryStats(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: AppColors.bgSurface,
      child: TextField(
        controller: widget.searchController,
        onChanged: widget.onSearchChanged,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: widget.searchHint,
          hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
          suffixIcon: widget.searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, size: 18, color: AppColors.textMuted),
                  onPressed: () {
                    widget.searchController.clear();
                    widget.onSearchChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.bgLight,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.brandNavy, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.filterTabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = widget.filterTabs[index];
          final isActive = tab.label.toUpperCase() == widget.activeFilter.toUpperCase();
          return Center(
            child: FilterChipWithCount(
              label: tab.label,
              count: tab.count,
              isSelected: isActive,
              onTap: () => widget.onFilterChanged(tab.label),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryStats() {
    final s = widget.summary!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          _buildStatItem('Total', AmountFormat.format(s.totalAmount), AppColors.textPrimary),
          Container(width: 1, height: 24, color: AppColors.borderLight, margin: const EdgeInsets.symmetric(horizontal: 12)),
          _buildStatItem('Received', AmountFormat.format(s.paidAmount), AppColors.success),
          Container(width: 1, height: 24, color: AppColors.borderLight, margin: const EdgeInsets.symmetric(horizontal: 12)),
          _buildStatItem('Pending', AmountFormat.format(s.pendingAmount), AppColors.warning),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: valueColor, fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    if (widget.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.emptyIcon, size: 56, color: AppColors.textMuted.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text(widget.emptyTitle,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Text(widget.emptySubtitle,
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 80),
        itemCount: widget.items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 0),
        itemBuilder: (context, index) {
          final item = widget.items[index];
          if (widget.itemBuilder != null) {
            return widget.itemBuilder!(context, item, index);
          }
          return CompactDocumentCard(
            docNumber: item.docNumber,
            partyName: item.partyName,
            date: item.date,
            amount: item.amount,
            status: item.status,
            balanceLabel: item.balanceLabel,
            balanceAmount: item.balanceAmount,
            onTap: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (ctx) => widget.detailBuilder(ctx, item)));
            },
          );
        },
      ),
    );
  }
}
