import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/misc_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart' hide AppCard, AppEmptyState;
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/shared/design_system.dart';

class ReminderListView extends StatefulWidget {
  const ReminderListView({super.key});

  @override
  State<ReminderListView> createState() => _ReminderListViewState();
}

class _ReminderListViewState extends State<ReminderListView> {
  List<dynamic> _reminders = [];
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    final result = await context.read<MiscProvider>().fetchReminders();
    if (mounted) {
      setState(() {
        _reminders = result;
        _isLoading = false;
      });
    }
  }

  List<dynamic> get _filtered {
    var list = _reminders;
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) {
        final title = (r['title'] ?? '').toString().toLowerCase();
        final message = (r['message'] ?? '').toString().toLowerCase();
        return title.contains(q) || message.contains(q);
      }).toList();
    }
    if (_filter == 'OVERDUE') {
      list = list.where((r) => r['is_overdue'] == true).toList();
    } else if (_filter == 'UPCOMING') {
      list = list.where((r) => r['is_overdue'] != true).toList();
    }
    return list;
  }

  void _dismiss(int index) {
    setState(() => _reminders.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final filtered = _filtered;
    final overdueCount = _reminders.where((r) => r['is_overdue'] == true).length;
    final upcomingCount = _reminders.where((r) => r['is_overdue'] != true).length;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        appBar: AppBar(title: const Text('Reminders')),
        body: const LoadingState(message: 'Loading reminders...'),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          if (!isMobile)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: AppButton(
                label: 'New Reminder',
                icon: Icons.add,
                isPrimary: true,
                onTap: () => _showCreateDialog(),
              ),
            ),
        ],
      ),
      floatingActionButton: isMobile
          ? FloatingActionButton(
              onPressed: () => _showCreateDialog(),
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: Column(
          children: [
            // ── Search + Filter ──
            AppCard(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppInput(
                          controller: _searchCtrl,
                          hint: 'Search reminders...',
                          prefix: const Icon(Icons.search_rounded, size: 18),
                          suffix: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () { _searchCtrl.clear(); setState(() {}); },
                                )
                              : null,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChipWithCount(
                          label: 'All',
                          count: _reminders.length,
                          isSelected: _filter == 'ALL',
                          onTap: () => setState(() => _filter = 'ALL'),
                        ),
                        const SizedBox(width: 4),
                        FilterChipWithCount(
                          label: 'Overdue',
                          count: overdueCount,
                          isSelected: _filter == 'OVERDUE',
                          onTap: () => setState(() => _filter = 'OVERDUE'),
                        ),
                        const SizedBox(width: 4),
                        FilterChipWithCount(
                          label: 'Upcoming',
                          count: upcomingCount,
                          isSelected: _filter == 'UPCOMING',
                          onTap: () => setState(() => _filter = 'UPCOMING'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── List ──
            Expanded(
              child: filtered.isEmpty
                  ? AppEmptyState(
                      icon: Icons.notifications_outlined,
                      title: 'No Reminders',
                      subtitle: _searchCtrl.text.isNotEmpty || _filter != 'ALL'
                          ? 'Try clearing your filters'
                          : 'Payment reminders for overdue invoices will appear here',
                      actionLabel: 'New Reminder',
                      onAction: () => _showCreateDialog(),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 20,
                        vertical: 8,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final r = filtered[i];
                        final isOverdue = r['is_overdue'] == true;
                        final dueDate = r['due_date']?.toString();
                        final amount = double.tryParse((r['amount'] ?? 0).toString()) ?? 0.0;
                        final invoiceNumber = r['invoice_number']?.toString();

                        return Dismissible(
                          key: Key('reminder_${r['id'] ?? i}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: AppColors.success,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('Mark Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                SizedBox(width: 8),
                                Icon(Icons.check_circle, color: Colors.white),
                              ],
                            ),
                          ),
                          onDismissed: (_) => _dismiss(i),
                          child: AppCard(
                            padding: const EdgeInsets.all(0),
                            child: AppListTile(
                              leadingText: isOverdue ? '!' : '${i + 1}',
                              title: r['title'] ?? 'Reminder',
                              subtitle: '${r['message'] ?? ''}${invoiceNumber != null ? ' • #$invoiceNumber' : ''}${dueDate != null ? ' • Due ${AppDate.format(dueDate)}' : ''}',
                              trailing: amount > 0 ? AmountFormat.format(amount) : null,
                              badge: isOverdue
                                  ? StatusBadge(label: 'OVERDUE', color: AppColors.error, backgroundColor: AppColors.errorBg)
                                  : StatusBadge(label: 'UPCOMING', color: AppColors.info, backgroundColor: AppColors.infoBg),
                              hoverActions: [
                                Tooltip(
                                  message: 'Mark Done',
                                  child: GestureDetector(
                                    onTap: () => _dismiss(i),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: AppColors.success.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Icon(Icons.check_circle, size: 14, color: AppColors.success),
                                    ),
                                  ),
                                ),
                              ],
                              onTap: () {
                                // Navigate to invoice detail if linked
                                if (r['invoice_id'] != null) {
                                  // Navigator.push(...InvoiceDetailView...)
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog() {
    final titleCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Reminder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            TextField(controller: messageCtrl, decoration: const InputDecoration(labelText: 'Message')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              if (titleCtrl.text.isNotEmpty) {
                setState(() {
                  _reminders.insert(0, {
                    'id': DateTime.now().millisecondsSinceEpoch,
                    'title': titleCtrl.text,
                    'message': messageCtrl.text,
                    'is_overdue': false,
                  });
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    ).whenComplete(() {
      titleCtrl.dispose();
      messageCtrl.dispose();
    });
  }
}
