/// Delivery Challan list screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/tables/table_pagination.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/features/offline_repository_providers.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import 'delivery_challan_form_screen.dart';

@immutable
class DeliveryChallanListItem {
  const DeliveryChallanListItem({
    required this.id,
    this.challanNumber = '',
    this.challanDate = '',
    this.dueDate = '',
    this.status = 'DRAFT',
    this.total = 0,
    this.contactName = '',
    this.createdAt,
  });

  final String id;
  final String challanNumber;
  final String challanDate;
  final String dueDate;
  final String status;
  final double total;
  final String contactName;
  final String? createdAt;

  factory DeliveryChallanListItem.fromJson(Map<String, dynamic> json) =>
      DeliveryChallanListItem(
        id: (json['id'] ?? '').toString(),
        challanNumber: json['challan_number'] as String? ?? '',
        challanDate: json['challan_date'] as String? ?? '',
        dueDate: json['due_date'] as String? ?? '',
        status: json['status'] as String? ?? 'DRAFT',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        contactName: json['contact_name'] as String? ?? '',
        createdAt: json['created_at'] as String?,
      );
}

class DeliveryChallanListQuery {
  const DeliveryChallanListQuery({this.page = 1, this.limit = 25, this.status});

  final int page, limit;
  final String? status;
}

final deliveryChallanListProvider = StreamProvider.autoDispose
    .family<
      ({List<DeliveryChallanListItem> items, int total}),
      DeliveryChallanListQuery
    >((ref, query) {
      final repo = ref.watch(salesRepositoryProvider);
      return repo.watchDeliveries().map((list) {
        final rawItems = list.map((item) {
          return DeliveryChallanListItem(
            id: item.localId,
            challanNumber: item.localId.substring(0, 8).toUpperCase(),
            challanDate: item.deliveryDate,
            dueDate: item.deliveryDate,
            status: item.lifecycleStatus.toUpperCase(),
            total: 0.0,
            contactName: item.customerName,
            createdAt: item.createdAt.toIso8601String(),
          );
        }).toList();
        final items = query.status == null
            ? rawItems
            : rawItems.where((e) => e.status == query.status).toList();
        return (items: items, total: items.length);
      });
    });

final _dcTableCtrlProvider =
    ChangeNotifierProvider.autoDispose<ApexTableController>(
      (ref) => ApexTableController(),
    );

class DeliveryChallanListScreen extends ConsumerStatefulWidget {
  const DeliveryChallanListScreen({super.key});

  @override
  ConsumerState<DeliveryChallanListScreen> createState() =>
      _DeliveryChallanListScreenState();
}

class _DeliveryChallanListScreenState
    extends ConsumerState<DeliveryChallanListScreen> {
  late final ApexTableController _tableCtrl;
  DeliveryChallanListQuery _query = const DeliveryChallanListQuery(
    page: 1,
    limit: 25,
  );

  @override
  void initState() {
    super.initState();
    _tableCtrl = ref.read(_dcTableCtrlProvider);
    _tableCtrl.addListener(_onTableChange);
  }

  @override
  void dispose() {
    _tableCtrl.removeListener(_onTableChange);
    super.dispose();
  }

  void _onTableChange() {
    final s = _tableCtrl.value;
    setState(() {
      _query = DeliveryChallanListQuery(
        page: s.page,
        limit: s.limit,
        status: s.statusFilter,
      );
    });
  }

  Future<void> _workflowAction(
    DeliveryChallanListItem item,
    String action,
  ) async {
    try {
      final suffix = action == 'issue' ? 'issue' : 'convert-to-invoice';
      await ref
          .read(apiClientProvider)
          .post('/delivery-challans/${item.id}/$suffix');
      ref.invalidate(deliveryChallanListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'issue'
                  ? 'Delivery challan issued.'
                  : 'Draft invoice created.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncPaged = ref.watch(deliveryChallanListProvider(_query));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    return Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Delivery Challans',
            subtitle: 'Dispatch documents for customer deliveries.',
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New Challan'),
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const DeliveryChallanFormScreen(),
                      ),
                    )
                    .then((_) => ref.invalidate(deliveryChallanListProvider)),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              ResponsiveLayout.isMobile(context) ? 12 : 24,
              0,
              ResponsiveLayout.isMobile(context) ? 12 : 24,
              8,
            ),
            child: _StatusFilterBar(controller: _tableCtrl),
          ),
          Expanded(
            child: asyncPaged.when(
              loading: () => ShimmerSkeleton(
                child: Column(
                  children: [
                    for (int i = 0; i < 6; i++)
                      const TableRowSkeleton(columns: 5),
                  ],
                ),
              ),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(deliveryChallanListProvider),
              ),
              data: (data) {
                if (data.items.isEmpty) {
                  final filtering = _query.status != null;
                  return EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: filtering
                        ? 'No matching challans'
                        : 'No delivery challans yet',
                    subtitle: filtering
                        ? 'Try clearing the status filter.'
                        : 'Create a delivery challan to record dispatch.',
                    actionLabel: filtering ? null : 'New Challan',
                    onAction: filtering
                        ? null
                        : () => Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const DeliveryChallanFormScreen(),
                                ),
                              )
                              .then(
                                (_) =>
                                    ref.invalidate(deliveryChallanListProvider),
                              ),
                  );
                }
                final paged = Paged<DeliveryChallanListItem>(
                  items: data.items,
                  total: data.total,
                  page: _query.page,
                  limit: _query.limit,
                );
                return Column(
                  children: [
                    Expanded(
                      child: _TableBody(
                        items: data.items,
                        colors: colors,
                        fmt: fmt,
                        onWorkflow: _workflowAction,
                      ),
                    ),
                    ApexPaginationControls(
                      controller: _tableCtrl,
                      paged: paged,
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
}

class _TableBody extends StatelessWidget {
  const _TableBody({
    required this.items,
    required this.colors,
    required this.fmt,
    required this.onWorkflow,
  });

  final List<DeliveryChallanListItem> items;
  final ApexColors colors;
  final NumberFormatter fmt;
  final void Function(DeliveryChallanListItem, String) onWorkflow;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (MediaQuery.sizeOf(context).width < 600) {
      return _MobileDeliveryChallanList(
        items: items,
        colors: colors,
        fmt: fmt,
        onWorkflow: onWorkflow,
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 800,
        child: Column(
          children: [
            Container(
              color: colors.surfaceMuted,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _header('CHALLAN #', 140, colors),
                  _header('Customer', 180, colors),
                  _header('Date', 100, colors),
                  _header('Due', 100, colors),
                  _header('Total', 120, colors, alignRight: true),
                  _header('Status', 120, colors),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: colors.border),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  return InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              DeliveryChallanFormScreen(editId: item.id),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(
                              item.challanNumber,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: Text(
                              item.contactName,
                              style: textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              item.challanDate,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              item.dueDate,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: MonetaryText(
                              value: fmt.currency(item.total),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: StatusBadge(
                              label: item.status,
                              tone: toneForStatus(item.status),
                            ),
                          ),
                          if (item.status == 'DRAFT' || item.status == 'ISSUED')
                            PopupMenuButton<String>(
                              tooltip: 'Workflow actions',
                              onSelected: (value) => onWorkflow(item, value),
                              itemBuilder: (_) => [
                                if (item.status == 'DRAFT')
                                  const PopupMenuItem(
                                    value: 'issue',
                                    child: Text('Issue challan'),
                                  ),
                                if (item.status == 'ISSUED')
                                  const PopupMenuItem(
                                    value: 'invoice',
                                    child: Text('Create invoice'),
                                  ),
                              ],
                            ),
                        ],
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

  Widget _header(
    String label,
    double width,
    ApexColors colors, {
    bool alignRight = false,
  }) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: colors.textMuted,
        ),
      ),
    );
  }
}

/// Mobile card layout for delivery challans. Mirrors the pattern from
/// InvoiceTableBody._MobileInvoiceList so the experience is consistent.
class _MobileDeliveryChallanList extends StatelessWidget {
  const _MobileDeliveryChallanList({
    required this.items,
    required this.colors,
    required this.fmt,
    required this.onWorkflow,
  });

  final List<DeliveryChallanListItem> items;
  final ApexColors colors;
  final NumberFormatter fmt;
  final void Function(DeliveryChallanListItem, String) onWorkflow;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No delivery challans found.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = items[i];
        final overdue =
            DateTime.tryParse(item.dueDate)?.isBefore(DateTime.now()) == true;
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(ApexRadius.lg),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DeliveryChallanFormScreen(editId: item.id),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.challanNumber,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      StatusBadge(
                        label: item.status.replaceAll('_', ' '),
                        tone: toneForStatus(item.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 15,
                        color: colors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.contactName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 15,
                        color: colors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        overdue
                            ? 'Overdue ${item.dueDate}'
                            : 'Due ${item.dueDate}',
                        style: TextStyle(
                          fontSize: 12,
                          color: overdue ? colors.warning : colors.textMuted,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        fmt.currency(item.total),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.controller});
  final ApexTableController controller;

  static const _options = [
    ('All', null),
    ('Draft', 'DRAFT'),
    ('Issued', 'ISSUED'),
    ('Cancelled', 'CANCELLED'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, _) {
        final active = state.statusFilter;
        return Container(
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(ApexRadius.md),
            border: Border.all(color: colors.border),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _options.map((o) {
              final selected = active == o.$2;
              return GestureDetector(
                onTap: () => controller.setStatusFilter(o.$2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? colors.surfaceRaised : Colors.transparent,
                    borderRadius: BorderRadius.circular(ApexRadius.sm),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    o.$1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? colors.primary : colors.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
