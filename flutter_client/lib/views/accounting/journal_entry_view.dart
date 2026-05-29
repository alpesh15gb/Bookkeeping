import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/accounting/journal_entry_form_view.dart';

class JournalEntryView extends StatefulWidget {
  const JournalEntryView({super.key});

  @override
  State<JournalEntryView> createState() => _JournalEntryViewState();
}

class _JournalEntryViewState extends State<JournalEntryView> {
  List<dynamic> _journals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _fetch() async {
    final list = await context.read<AccountingProvider>().fetchJournals();
    if (mounted) {
      setState(() {
        _journals = list;
        _isLoading = false;
      });
    }
  }

  void _showForm() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const JournalEntryFormView(),
      ),
    ).then((updated) {
      if (updated == true) _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: _showForm,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading journal entries...')
          : _journals.isEmpty
              ? EmptyState(
                  icon: Icons.book_outlined,
                  title: 'No journal entries',
                  subtitle: 'Journal entries will appear here once recorded',
                  actionLabel: 'New Journal Entry',
                  onAction: _showForm,
                )
              : ListView.separated(
                  padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
                  itemCount: _journals.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final journal = _journals[i];
                    final List lines = journal['lines'] ?? [];
                    final amount = lines.isNotEmpty ? lines[0]['amount'] : 0.0;
                    return AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                journal['reference_number'] ?? 'JV',
                                style: AppTextStyles.h3,
                              ),
                              StatusBadge(label: journal['source_type'] ?? 'MANUAL'),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            journal['description'] ?? 'No description',
                            style: AppTextStyles.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Date: ${journal['entry_date']}',
                            style: AppTextStyles.caption,
                          ),
                          const SizedBox(height: 10),
                          const Divider(),
                          const SizedBox(height: 6),
                          // Display brief posting preview lines
                          ...lines.take(2).map((l) {
                            final dir = l['direction'] == 'DEBIT' ? 'Dr' : 'Cr';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${l['account_name']} ($dir)',
                                    style: AppTextStyles.caption,
                                  ),
                                  Text(
                                    '₹${double.parse(l['amount'].toString()).toStringAsFixed(2)}',
                                    style: AppTextStyles.numeric,
                                  ),
                                ],
                              ),
                            );
                          }),
                          if (lines.length > 2)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '+ ${lines.length - 2} more lines',
                                style: AppTextStyles.caption.copyWith(fontStyle: FontStyle.italic),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
