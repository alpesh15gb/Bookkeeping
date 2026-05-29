import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/credit_notes/credit_debit_note_form_view.dart';
import 'package:flutter_client/views/credit_notes/credit_debit_note_detail_view.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Cancel failed'), backgroundColor: AppColors.error),
        );
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
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: AppColors.bgSurface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Credit Notes'),
              Tab(text: 'Debit Notes'),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(isCredit: _tabController.index == 0),
        child: const Icon(Icons.add),
      ),
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
    final isMobile = AdaptiveLayout.isMobile(context);
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.compare_arrows_outlined,
        title: 'No ${type}s',
        subtitle: '${type}s will appear here once created',
        actionLabel: 'Create $type',
        onAction: () => _showForm(isCredit: isCredit),
      );
    }
    return ListView.separated(
      padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
      itemCount: list.length,
      separatorBuilder: (context, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final note = list[i];
        final numVal = type == 'Credit Note' ? note['credit_note_number'] : note['debit_note_number'];
        return AppCard(
          onTap: () => _showDetail(note['id'], isCredit),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(numVal?.toString() ?? 'NOTE', style: AppTextStyles.h3)),
                  if (note['status'] != null) StatusBadge(label: note['status']),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(note['issue_date'] ?? '', style: AppTextStyles.caption),
                  if (note['invoice_number'] != null) ...[
                    const SizedBox(width: 16),
                    Icon(Icons.description_outlined, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text('Inv: ${note['invoice_number']}', style: AppTextStyles.bodySmall),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('₹${double.parse((note['total'] ?? 0).toString()).toStringAsFixed(2)}', style: AppTextStyles.numericLarge),
                  Row(
                    children: [
                      if (note['status'] == 'DRAFT') ...[
                        OutlinedButton.icon(
                          onPressed: () => _showForm(note: note, isCredit: isCredit),
                          icon: const Icon(Icons.edit_outlined, size: 14),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            textStyle: AppTextStyles.buttonSmall,
                            side: const BorderSide(color: AppColors.borderInput),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (note['status'] != 'CANCELLED')
                        OutlinedButton.icon(
                          onPressed: () => _cancelNote(note['id'], isCredit),
                          icon: const Icon(Icons.cancel_outlined, size: 14),
                          label: const Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            textStyle: AppTextStyles.buttonSmall,
                            side: BorderSide(color: AppColors.error.withOpacity(0.3)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
