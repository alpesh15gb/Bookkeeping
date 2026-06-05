import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart' hide AppCard, AppEmptyState;
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/credit_notes/credit_debit_note_form_view.dart';
import 'package:flutter_client/views/credit_notes/credit_debit_note_detail_view.dart';
import 'package:flutter_client/views/shared/toast.dart';

class CreditNoteListView extends StatefulWidget {
  const CreditNoteListView({super.key});

  @override
  State<CreditNoteListView> createState() => _CreditNoteListViewState();
}

class _CreditNoteListViewState extends State<CreditNoteListView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _creditNotes = [];
  List<dynamic> _debitNotes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetch();
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: AppColors.bgSurface,
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                  labelStyle: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                  unselectedLabelStyle: AppTextStyles.caption,
                  indicatorWeight: 2,
                  tabs: const [
                    Tab(text: 'Credit Notes'),
                    Tab(text: 'Debit Notes'),
                  ],
                ),
              ),
              if (!isMobile)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: AppButton(
                    label: _tabController.index == 0 ? 'Create Credit Note' : 'Create Debit Note',
                    icon: Icons.add,
                    isPrimary: true,
                    isSmall: true,
                    onTap: () => _showForm(isCredit: _tabController.index == 0),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: isMobile
          ? FloatingActionButton(
              onPressed: () => _showForm(isCredit: _tabController.index == 0),
              child: const Icon(Icons.add),
            )
          : null,
      body: _isLoading
          ? const LoadingState(message: 'Loading notes...')
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_creditNotes, 'Credit Note', true),
                _buildList(_debitNotes, 'Debit Note', false),
              ],
            ),
    );
  }

  Widget _buildList(List<dynamic> list, String type, bool isCredit) {
    if (list.isEmpty) {
      return AppEmptyState(
        icon: Icons.compare_arrows_outlined,
        title: 'No ${type}s',
        subtitle: '${type}s will appear here once created',
        actionLabel: 'Create $type',
        onAction: () => _showForm(isCredit: isCredit),
      );
    }

    num totalAmount = 0;
    for (final n in list) {
      totalAmount += double.tryParse((n['total'] ?? 0).toString()) ?? 0;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: HeroSummaryCard(
            title: 'Total ${type}s',
            amount: totalAmount,
            subtitle: '${list.length} notes',
            icon: Icons.compare_arrows_outlined,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8, left: 12, right: 12, bottom: 80),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final note = list[i];
              final numVal = (isCredit ? note['credit_note_number'] : note['debit_note_number'])?.toString() ?? 'NOTE';
              final total = double.tryParse((note['total'] ?? 0).toString()) ?? 0;
              final status = note['status']?.toString() ?? 'DRAFT';

              final itemActions = <Widget>[
                if (status == 'DRAFT')
                  _CompactAction(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit',
                    onTap: () => _showForm(note: note, isCredit: isCredit),
                  ),
                if (status != 'CANCELLED')
                  _CompactAction(
                    icon: Icons.cancel_outlined,
                    tooltip: 'Cancel',
                    color: AppColors.error,
                    onTap: () => _cancelNote(note['id'], isCredit),
                  ),
              ];

              return AppListTile(
                leadingText: numVal,
                title: note['invoice_number'] != null ? 'Inv: ${note['invoice_number']}' : numVal,
                subtitle: '${AppDate.format(note['issue_date']?.toString())} \u00b7 $status',
                trailingWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppAmount(amount: total),
                    const SizedBox(width: 8),
                    StatusBadge(label: status),
                    if (itemActions.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      ...itemActions,
                    ],
                  ],
                ),
                onTap: () => _showDetail(note['id'], isCredit),
              );
            },
          ),
        ),
      ],
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
