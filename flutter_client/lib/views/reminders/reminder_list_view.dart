import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/misc_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class ReminderListView extends StatefulWidget {
  const ReminderListView({super.key});

  @override
  State<ReminderListView> createState() => _ReminderListViewState();
}

class _ReminderListViewState extends State<ReminderListView> {
  List<dynamic> _reminders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const LoadingState(message: 'Loading reminders...');

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _reminders.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.notifications_outlined,
                    title: 'No Payment Reminders',
                    subtitle: 'Payment reminders for overdue invoices will appear here',
                  ),
                ],
              )
            : ListView.builder(
                padding: AppSpacing.pagePadding,
                itemCount: _reminders.length,
                itemBuilder: (context, i) {
                  final r = _reminders[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: AppRadius.card,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC6803).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.notifications_outlined, size: 18, color: Color(0xFFDC6803)),
                      ),
                      title: Text(r['title'] ?? 'Reminder', style: AppTextStyles.h3),
                      subtitle: Text(r['message'] ?? '', style: AppTextStyles.caption),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
