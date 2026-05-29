import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/invoice_provider.dart';
import 'package:flutter_client/models/invoice.dart';
import 'package:flutter_client/views/invoices/invoice_form_view.dart';
import 'package:flutter_client/views/invoices/invoice_detail_view.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class InvoiceListView extends StatefulWidget {
  const InvoiceListView({super.key});

  @override
  State<InvoiceListView> createState() => _InvoiceListViewState();
}

class _InvoiceListViewState extends State<InvoiceListView> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'ALL';

  final _statusOptions = ['ALL', 'DRAFT', 'SENT', 'PARTIALLY_PAID', 'PAID', 'CANCELLED'];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _fetch());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _fetch() {
    context.read<InvoiceProvider>().fetchInvoices(
      search: _searchCtrl.text.trim().isNotEmpty ? _searchCtrl.text.trim() : null,
      status: _statusFilter == 'ALL' ? null : _statusFilter,
    );
  }

  void _showForm({InvoiceModel? invoice}) async {
    InvoiceModel? fullInvoice = invoice;
    if (invoice != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      fullInvoice = await context.read<InvoiceProvider>().fetchInvoiceDetail(invoice.id);
      if (mounted) Navigator.pop(context);
      if (fullInvoice == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load invoice details'), backgroundColor: AppColors.error),
          );
        }
        return;
      }
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvoiceFormView(editInvoice: fullInvoice),
        ),
      ).then((_) {
        if (mounted) _fetch();
      });
    }
  }

  void _showDetail(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailView(invoiceId: id)),
    ).then((_) => _fetch());
  }

  Future<void> _cancelInvoice(InvoiceModel invoice) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel Invoice?',
      message: 'Cancel ${invoice.invoiceNumber}? This will reverse ledger entries.',
    );
    if (confirm == true) {
      final provider = context.read<InvoiceProvider>();
      final success = await provider.cancelInvoice(invoice.id);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Cancel failed'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InvoiceProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // ── Search + Filter Bar ──
          Container(
            color: AppColors.bgSurface,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: 10,
            ),
            child: Column(
              children: [
                // Search field
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by invoice number or party...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              _fetch();
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.borderInput),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.borderInput),
                    ),
                  ),
                  onSubmitted: (_) => _fetch(),
                  onChanged: (v) {
                    if (v.isEmpty) _fetch();
                    setState(() {}); // update suffix icon
                  },
                ),
                const SizedBox(height: 8),
                // Status filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _statusOptions.map((s) {
                      final isSelected = _statusFilter == s;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(
                            s == 'ALL' ? 'All' : s.replaceAll('_', ' '),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _statusFilter = s);
                            _fetch();
                          },
                          selectedColor: AppColors.brandNavy,
                          backgroundColor: AppColors.borderLight,
                          side: BorderSide.none,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // ── List Body ──
          Expanded(
            child: provider.isLoading && provider.invoices.isEmpty
                ? const LoadingState(message: 'Loading invoices...')
                : provider.errorMessage != null && provider.invoices.isEmpty
                    ? ErrorState(message: provider.errorMessage!, onRetry: _fetch)
                    : provider.invoices.isEmpty
                        ? EmptyState(
                            icon: Icons.description_outlined,
                            title: 'No invoices found',
                            subtitle: _statusFilter != 'ALL' || _searchCtrl.text.isNotEmpty
                                ? 'Try clearing your filters'
                                : 'Create your first invoice to get started',
                            actionLabel: 'Create Invoice',
                            onAction: () => _showForm(),
                          )
                        : RefreshIndicator(
                            onRefresh: () async => _fetch(),
                            child: ListView.separated(
                              padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
                              itemCount: provider.invoices.length,
                              separatorBuilder: (context, _) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final invoice = provider.invoices[i];
                                return AppCard(
                                  onTap: () => _showDetail(invoice.id),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(invoice.invoiceNumber, style: AppTextStyles.h3),
                                          ),
                                          StatusBadge.fromInvoiceStatus(invoice.status),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(Icons.person_outlined, size: 14, color: AppColors.textMuted),
                                          const SizedBox(width: 6),
                                          Text(invoice.contact?.name ?? 'N/A', style: AppTextStyles.bodySmall),
                                          const SizedBox(width: 16),
                                          Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textMuted),
                                          const SizedBox(width: 6),
                                          Text(invoice.issueDate, style: AppTextStyles.caption),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('₹${invoice.total.toStringAsFixed(2)}', style: AppTextStyles.numericLarge),
                                              if (invoice.amountPaid > 0)
                                                Text(
                                                  'Paid: ₹${invoice.amountPaid.toStringAsFixed(2)}',
                                                  style: AppTextStyles.caption.copyWith(color: AppColors.success),
                                                ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              OutlinedButton.icon(
                                                onPressed: () => _showForm(invoice: invoice),
                                                icon: const Icon(Icons.edit_outlined, size: 14),
                                                label: const Text('Edit'),
                                                style: OutlinedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  textStyle: AppTextStyles.buttonSmall,
                                                  side: const BorderSide(color: AppColors.borderInput),
                                                ),
                                              ),
                                              if (invoice.status == 'SENT' || invoice.status == 'PARTIALLY_PAID') ...[
                                                const SizedBox(width: 8),
                                                OutlinedButton.icon(
                                                  onPressed: () => _cancelInvoice(invoice),
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
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
