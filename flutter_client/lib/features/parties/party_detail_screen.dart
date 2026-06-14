import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../models/contact.dart';
import '../../../models/invoice.dart';
import '../../../models/payment.dart';
import '../../../providers/contact_provider.dart';
import '../../../providers/invoice_provider.dart';
import '../../../providers/payment_provider.dart';

class PartyDetailScreen extends StatefulWidget {
  final String id;
  const PartyDetailScreen({super.key, required this.id});

  @override
  State<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyDetailScreenState extends State<PartyDetailScreen> {
  ContactModel? _contact;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final contactProv = context.read<ContactProvider>();
      await contactProv.fetchContacts();
      _contact = contactProv.contacts.where((c) => c.id == widget.id).firstOrNull;

      final invoiceProv = context.read<InvoiceProvider>();
      await invoiceProv.fetchInvoices();

      final paymentProv = context.read<PaymentProvider>();
      await paymentProv.fetchReceipts();
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_contact == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 48, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text('Party not found', style: AppTypography.headlineMedium),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: () => context.go('/parties'), child: const Text('Back to Parties')),
          ],
        ),
      );
    }

    final contact = _contact!;
    final invoices = context.watch<InvoiceProvider>().invoices
        .where((i) => i.contactId == widget.id).toList();
    final payments = context.watch<PaymentProvider>().receipts
        .where((p) => p.contactId == widget.id).toList();

    final totalRevenue = invoices.fold(0.0, (sum, i) => sum + i.total);
    final totalPaid = invoices.fold(0.0, (sum, i) => sum + i.amountPaid);
    final outstanding = totalRevenue - totalPaid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name, style: AppTypography.headlineLarge),
                Text(
                  '${_formatContactType(contact.contactType)} • ${_getStateName(contact.stateCode)}',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.gray500),
                ),
              ],
            ),
            const Spacer(),
            AppButton(
              label: 'Call',
              icon: Icons.phone,
              style: AppButtonStyle.secondary,
              onPressed: contact.phone != null ? () {} : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: 'WhatsApp',
              icon: Icons.chat,
              style: AppButtonStyle.secondary,
              onPressed: contact.phone != null ? () {} : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: 'Record Payment',
              icon: Icons.payments,
              onPressed: outstanding > 0 ? () {} : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        DefaultTabController(
          length: 4,
          child: Expanded(
            child: Column(
              children: [
                TabBar(
                  tabs: [
                    const Tab(text: 'Overview'),
                    Tab(text: 'Invoices (${invoices.length})'),
                    Tab(text: 'Payments (${payments.length})'),
                    const Tab(text: 'Details'),
                  ],
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.gray500,
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildOverviewTab(contact, invoices, payments, totalRevenue, outstanding, totalPaid),
                      _buildInvoicesTab(invoices),
                      _buildPaymentsTab(payments),
                      _buildDetailsTab(contact),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab(
    ContactModel contact,
    List<InvoiceModel> invoices,
    List<PaymentModel> payments,
    double totalRevenue,
    double outstanding,
    double totalPaid,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppKpiCard(
                  icon: Icons.trending_up,
                  label: 'LIFETIME REVENUE',
                  value: '₹${_formatAmount(totalRevenue)}',
                  iconColor: AppColors.success,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppKpiCard(
                  icon: Icons.trending_down,
                  label: 'OUTSTANDING',
                  value: '₹${_formatAmount(outstanding)}',
                  iconColor: outstanding > 0 ? AppColors.error : AppColors.success,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppKpiCard(
                  icon: Icons.payments,
                  label: 'TOTAL PAID',
                  value: '₹${_formatAmount(totalPaid)}',
                  iconColor: AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppSectionHeader(title: 'CONTACT INFORMATION'),
                      const SizedBox(height: AppSpacing.md),
                      if (contact.phone != null) _buildContactRow(Icons.phone, contact.phone!),
                      if (contact.email != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _buildContactRow(Icons.email, contact.email!),
                      ],
                      const Divider(height: AppSpacing.xl),
                      Text('BILLING ADDRESS', style: AppTypography.labelMedium),
                      const SizedBox(height: AppSpacing.sm),
                      Text(_formatAddress(contact.billingAddress), style: AppTypography.bodySmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(
                width: 280,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppSectionHeader(title: 'GST DETAILS'),
                      const SizedBox(height: AppSpacing.md),
                      _buildInfoRow('GSTIN', contact.gstin ?? 'N/A'),
                      const SizedBox(height: AppSpacing.sm),
                      _buildInfoRow('Type', contact.registrationType),
                      const SizedBox(height: AppSpacing.sm),
                      _buildInfoRow('State', _getStateName(contact.stateCode)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvoicesTab(List<InvoiceModel> invoices) {
    if (invoices.isEmpty) {
      return AppEmptyState(icon: Icons.receipt_long, title: 'No invoices');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: invoices.length,
      itemBuilder: (context, index) {
        final inv = invoices[index];
        final balance = inv.total - inv.amountPaid;
        final status = _parseStatus(inv.status);

        return AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          onTap: () => context.go('/invoices/${inv.id}'),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inv.invoiceNumber, style: AppTypography.labelLarge),
                    Text(_formatDate(inv.issueDate), style: AppTypography.bodySmall.copyWith(color: AppColors.gray500)),
                  ],
                ),
              ),
              Expanded(child: AppAmountText(amount: inv.total, style: AppTypography.amountTiny)),
              Expanded(child: AppAmountText(amount: balance, style: AppTypography.amountTiny)),
              AppStatusBadge(status: status, isCompact: true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaymentsTab(List<PaymentModel> payments) {
    if (payments.isEmpty) {
      return AppEmptyState(icon: Icons.payments, title: 'No payments');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: payments.length,
      itemBuilder: (context, index) {
        final p = payments[index];
        return AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.paymentMode, style: AppTypography.labelLarge),
                    Text(_formatDate(p.paymentDate), style: AppTypography.bodySmall.copyWith(color: AppColors.gray500)),
                  ],
                ),
              ),
              AppAmountText(amount: p.amount, style: AppTypography.amountTiny),
              const SizedBox(width: AppSpacing.md),
              AppStatusBadge(
                status: p.status == 'COMPLETED' ? InvoiceStatus.paid : InvoiceStatus.pending,
                isCompact: true,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailsTab(ContactModel contact) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionHeader(title: 'PARTY DETAILS'),
            const SizedBox(height: AppSpacing.md),
            _buildInfoRow('Name', contact.name),
            const SizedBox(height: AppSpacing.sm),
            _buildInfoRow('Type', _formatContactType(contact.contactType)),
            const SizedBox(height: AppSpacing.sm),
            _buildInfoRow('Phone', contact.phone ?? 'N/A'),
            const SizedBox(height: AppSpacing.sm),
            _buildInfoRow('Email', contact.email ?? 'N/A'),
            const SizedBox(height: AppSpacing.sm),
            _buildInfoRow('GSTIN', contact.gstin ?? 'N/A'),
            const SizedBox(height: AppSpacing.sm),
            _buildInfoRow('PAN', contact.pan ?? 'N/A'),
            const SizedBox(height: AppSpacing.sm),
            _buildInfoRow('Registration', contact.registrationType),
            const SizedBox(height: AppSpacing.sm),
            _buildInfoRow('State', _getStateName(contact.stateCode)),
          ],
        ),
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.gray400),
        const SizedBox(width: AppSpacing.sm),
        Text(value, style: AppTypography.bodyMedium),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodySmall),
        Text(value, style: AppTypography.labelMedium),
      ],
    );
  }

  InvoiceStatus _parseStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PAID': return InvoiceStatus.paid;
      case 'PARTIAL': return InvoiceStatus.partial;
      case 'OVERDUE': return InvoiceStatus.overdue;
      case 'DRAFT': return InvoiceStatus.draft;
      case 'CANCELLED': return InvoiceStatus.cancelled;
      default: return InvoiceStatus.pending;
    }
  }

  String _formatDate(String date) {
    if (date.isEmpty) return '-';
    try {
      final d = DateTime.parse(date);
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return date;
    }
  }

  String _formatAmount(double amount) {
    if (amount >= 10000000) return '${(amount / 10000000).toStringAsFixed(1)}Cr';
    if (amount >= 100000) return '${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }

  String _formatContactType(String type) {
    switch (type) {
      case 'CUSTOMER': return 'Customer';
      case 'VENDOR': return 'Vendor';
      case 'BOTH': return 'Both';
      default: return type;
    }
  }

  String _formatAddress(Map<String, dynamic> addr) {
    final parts = <String>[];
    if (addr['line1'] != null) parts.add(addr['line1'].toString());
    if (addr['line2'] != null) parts.add(addr['line2'].toString());
    if (addr['city'] != null) parts.add(addr['city'].toString());
    if (addr['state'] != null) parts.add(addr['state'].toString());
    if (addr['pincode'] != null) parts.add(addr['pincode'].toString());
    return parts.isEmpty ? 'No address' : parts.join(', ');
  }

  String _getStateName(String code) {
    const states = {
      '01': 'Jammu & Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh',
      '05': 'Uttarakhand', '06': 'Haryana', '07': 'Delhi', '08': 'Rajasthan',
      '09': 'Uttar Pradesh', '10': 'Bihar', '11': 'Sikkim', '12': 'Arunachal Pradesh',
      '13': 'Nagaland', '14': 'Manipur', '15': 'Mizoram', '16': 'Tripura',
      '17': 'Meghalaya', '18': 'Assam', '19': 'West Bengal', '20': 'Jharkhand',
      '21': 'Odisha', '22': 'Chhattisgarh', '23': 'Madhya Pradesh', '24': 'Gujarat',
      '25': 'Daman & Diu', '26': 'Dadra & Nagar Haveli', '27': 'Maharashtra',
      '28': 'Andhra Pradesh (Old)', '29': 'Karnataka', '30': 'Goa', '31': 'Lakshadweep',
      '32': 'Kerala', '33': 'Tamil Nadu', '34': 'Puducherry', '35': 'Andaman & Nicobar',
      '36': 'Telangana', '37': 'Andhra Pradesh', '38': 'Ladakh',
    };
    return states[code] ?? 'State $code';
  }
}
