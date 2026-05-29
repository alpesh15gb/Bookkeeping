import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/misc_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class AuditLogListView extends StatefulWidget {
  const AuditLogListView({super.key});

  @override
  State<AuditLogListView> createState() => _AuditLogListViewState();
}

class _AuditLogListViewState extends State<AuditLogListView> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    final result = await context.read<MiscProvider>().fetchAuditLogs();
    if (mounted) {
      setState(() {
        _data = result;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const LoadingState(message: 'Loading audit logs...');

    final items = (_data?['items'] as List?) ?? [];

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: items.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.history_rounded,
                    title: 'No Audit Logs',
                    subtitle: 'Audit trail entries will appear as actions are performed',
                  ),
                ],
              )
            : ListView.builder(
                padding: AppSpacing.pagePadding,
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final log = items[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: AppRadius.card,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(log['action'] ?? 'Unknown', style: AppTextStyles.h3)),
                            Text(log['created_at'] ?? '', style: AppTextStyles.caption),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          log['description'] ?? '',
                          style: AppTextStyles.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
