import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/shared/document_list_view.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/credit_notes/credit_debit_note_form_view.dart';
import 'package:flutter_client/views/credit_notes/credit_debit_note_detail_view.dart';

class CreditNoteListView extends StatefulWidget {
  const CreditNoteListView({super.key});

  @override
  State<CreditNoteListView> createState() => _CreditNoteListViewState();
}

class _CreditNoteListViewState extends State<CreditNoteListView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  List<dynamic> _creditNotes = [];
  List<dynamic> _debitNotes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _fetch() async {
    setState(() => _isLoading = true);
    final cn = await context.read<DocumentProvider>().fetchCreditNotes();
    final dn = await context.read<DocumentProvider>().fetchDebitNotes();
    if (mounted) {
      setState(() {
        _creditNotes = cn;
        _debitNotes = dn;
        _isLoading = false;
      });
    }
  }

  void _showForm({Map<String, dynamic>? note, required bool isCredit}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreditDebitNoteFormView(isCredit: isCredit, editNote: note),
      ),
    ).then((updated) {
      if (updated == true) _fetch();
    });
  }

  void _showDetail(String id, bool isCredit) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreditDebitNoteDetailView(noteId: id, isCredit: isCredit),
      ),
    ).then((_) => _fetch());
  }

  Future<void> _cancelNote(String id, bool isCredit) async {
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel?', message: 'Cancel this note?');
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = isCredit
          ? await provider.cancelCreditNote(id)
          : await provider.cancelDebitNote(id);
      if (success) {
        _fetch();
      } else if (mounted) {
        AppToast.error(context, provider.errorMessage ?? 'Cancel failed');
      }
    }
  }

  List<dynamic> _filterList(List<dynamic> list) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return list;
    return list.where((n) {
      final number = ((n['credit_note_number'] ?? n['debit_note_number']) ?? '').toString().toLowerCase();
      final invoice = (n['invoice_number'] ?? '').toString().toLowerCase();
      return number.contains(query) || invoice.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(isCredit: _tabController.index == 0),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.bgSurface,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.brandNavy,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.goldAccent,
              indicatorWeight: 3,
              labelStyle: AppTextStyles.tabLabel.copyWith(fontWeight: FontWeight.w700),
              unselectedLabelStyle: AppTextStyles.tabLabel,
              onTap: (_) => setState(() {}),
              tabs: const [
                Tab(text: 'CREDIT NOTES'),
                Tab(text: 'DEBIT NOTES'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const LoadingState(message: 'Loading notes...')
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTab(_creditNotes, 'Credit Note', true),
                      _buildTab(_debitNotes, 'Debit Note', false),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(List<dynamic> allItems, String type, bool isCredit) {
    final filtered = _filterList(allItems);

    final totalCount = allItems.length;
    final draftCount = allItems.where((e) => e['status'] == 'DRAFT').length;
    final postedCount = allItems.where((e) => e['status'] == 'POSTED').length;
    final cancelledCount = allItems.where((e) => e['status'] == 'CANCELLED').length;

    num totalAmount = 0;
    for (final n in allItems) {
      totalAmount += double.tryParse((n['total'] ?? 0).toString()) ?? 0;
    }

    final items = filtered.map((note) {
      final numVal = (isCredit ? note['credit_note_number'] : note['debit_note_number'])?.toString() ?? 'NOTE';
      return DocumentItemData(
        id: note['id'].toString(),
        docNumber: numVal,
        partyName: note['invoice_number'] != null ? 'Inv: ${note['invoice_number']}' : numVal,
        date: note['issue_date']?.toString(),
        amount: double.tryParse((note['total'] ?? 0).toString()) ?? 0,
        status: note['status'] ?? 'DRAFT',
      );
    }).toList();

    return DocumentListView(
      title: '${type}s',
      searchController: _searchCtrl,
      searchHint: 'Search ${type.toLowerCase()}s...',
      onSearchChanged: (_) => setState(() {}),
      filterTabs: [
        FilterTab('ALL', totalCount),
        FilterTab('DRAFT', draftCount),
        FilterTab('POSTED', postedCount),
        FilterTab('CANCELLED', cancelledCount),
      ],
      activeFilter: 'ALL',
      onFilterChanged: (_) {},
      summary: ListSummaryData(totalAmount: totalAmount.toDouble(), totalCount: totalCount),
      items: items,
      isLoading: false,
      onRefresh: () async => _fetch(),
      emptyTitle: 'No ${type}s',
      emptySubtitle: '${type}s will appear here once created',
      emptyIcon: Icons.compare_arrows_outlined,
      detailBuilder: (ctx, item) => CreditDebitNoteDetailView(noteId: item.id, isCredit: isCredit),
      itemBuilder: (context, item, index) {
        final itemActions = <Widget>[
          if (item.status == 'DRAFT')
            _CompactAction(
              icon: Icons.edit_outlined,
              tooltip: 'Edit',
              onTap: () {
                final match = allItems.firstWhere((e) => e['id'].toString() == item.id, orElse: () => {});
                _showForm(note: match, isCredit: isCredit);
              },
            ),
          if (item.status != 'CANCELLED')
            _CompactAction(
              icon: Icons.cancel_outlined,
              tooltip: 'Cancel',
              color: AppColors.error,
              onTap: () => _cancelNote(item.id, isCredit),
            ),
        ];

        return AppListTile(
          leadingText: item.docNumber,
          title: item.partyName ?? item.docNumber,
          subtitle: '${AppDate.format(item.date)} · ${item.status}',
          trailingWidget: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppAmount(amount: item.amount.toDouble()),
              const SizedBox(width: 8),
              StatusBadge(label: item.status),
              if (itemActions.isNotEmpty) ...[
                const SizedBox(width: 8),
                ...itemActions,
              ],
            ],
          ),
          onTap: () => _showDetail(item.id, isCredit),
        );
      },
    );
  }
}

class _CompactAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _CompactAction({
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: (color ?? AppColors.brandNavy).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 14, color: color ?? AppColors.brandNavy),
        ),
      ),
    );
  }
}
