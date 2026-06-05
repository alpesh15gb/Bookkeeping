import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/invoice_provider.dart';
import 'package:flutter_client/models/invoice.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/invoices/invoice_form_view.dart';
import 'package:flutter_client/core/print_share_helper.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/payments/payment_form_view.dart';

class InvoiceDetailView extends StatefulWidget {
  final String invoiceId;
  const InvoiceDetailView({super.key, required this.invoiceId});

  @override
  State<InvoiceDetailView> createState() => _InvoiceDetailViewState();
}

class _InvoiceDetailViewState extends State<InvoiceDetailView> {
  InvoiceModel? _invoice;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  void _fetchDetail() async {
    final detail = await context.read<InvoiceProvider>().fetchInvoiceDetail(widget.invoiceId);
    if (mounted) setState(() { _invoice = detail; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(_invoice?.invoiceNumber ?? 'Invoice'),
        actions: [
          if (_invoice != null) ...[
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 18),
              onPressed: _share,
              tooltip: 'Share',
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: _edit,
              tooltip: 'Edit',
            ),
            const SizedBox(width: 12),
          ],
        ],
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading invoice...')
          : _invoice == null
              ? const ErrorState(message: 'Invoice not found.')
              : isMobile
                  ? _buildMobileLayout()
                  : _buildDesktopLayout(),
    );
  }

  // ── Desktop: Two-column layout ──
  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left panel: Invoice details
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildDetailContent(),
          ),
        ),
        // Right panel: Actions
        Container(
          width: 280,
          margin: const EdgeInsets.only(right: 24, top: 24, bottom: 24),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildActionsPanel(),
          ),
        ),
      ],
    );
  }

  // ── Mobile: Single column ──
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDetailContent(),
          const SizedBox(height: 16),
          _buildActionsPanel(),
        ],
      ),
    );
  }

  // ── Detail Content ──
  Widget _buildDetailContent() {
    final inv = _invoice!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header: Amount + Status ──
        Container(
          padding: const EdgeInsets.all(16),
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
                  StatusBadge.fromInvoiceStatus(inv.status),
                  const Spacer(),
                  Text(
                    'Invoice',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                AmountFormat.format(inv.total),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 0.1,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '#${inv.invoiceNumber}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _infoRow('Customer', inv.contact?.name ?? inv.contactName ?? 'N/A'),
              _infoRow('Issue Date', inv.issueDate),
              _infoRow('Due Date', inv.dueDate),
              _infoRow('Amount Paid', AmountFormat.format(inv.amountPaid)),
              _infoRow('Balance', AmountFormat.format(inv.total - inv.amountPaid)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Items ──
        _sectionCard(
          title: 'Items',
          child: inv.lines.isEmpty
              ? _empty('No items')
              : Column(
                  children: [
                    // Header row
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.bgLight,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text('Item', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
                          ),
                          Expanded(
                            child: Text('Qty', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
                          ),
                          Expanded(
                            child: Text('Rate', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5), textAlign: TextAlign.right),
                          ),
                          Expanded(
                            child: Text('Total', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5), textAlign: TextAlign.right),
                          ),
                        ],
                      ),
                    ),
                    ...inv.lines.map((line) => _lineItemRow(line)),
                  ],
                ),
        ),
        const SizedBox(height: 16),

        // ── Tax Summary ──
        _sectionCard(
          title: 'Tax Summary',
          child: Column(
            children: [
              _summaryRow('Subtotal', inv.subtotal),
              if (inv.cgstAmount > 0) _summaryRow('CGST', inv.cgstAmount),
              if (inv.sgstAmount > 0) _summaryRow('SGST', inv.sgstAmount),
              if (inv.igstAmount > 0) _summaryRow('IGST', inv.igstAmount),
              if (inv.cessAmount > 0) _summaryRow('CESS', inv.cessAmount),
              if (inv.roundOff != 0) _summaryRow('Round Off', inv.roundOff),
              const Divider(height: 1),
              const SizedBox(height: 8),
              _summaryRow('Total', inv.total, isBold: true, color: AppColors.brandNavy),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Notes ──
        if (inv.notes != null && inv.notes!.isNotEmpty)
          _sectionCard(
            title: 'Notes',
            child: Text(inv.notes!, style: AppTextStyles.bodySmall),
          ),
      ],
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineItemRow(InvoiceLineModel line) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.productName ?? 'Product',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                ),
                if (line.hsnSac.isNotEmpty)
                  Text(
                    'HSN: ${line.hsnSac}',
                    style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              '${line.quantity.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          Expanded(
            child: Text(
              AmountFormat.format(line.rate),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            child: Text(
              AmountFormat.format(line.total),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 14 : 13,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            AmountFormat.format(value),
            style: TextStyle(
              fontSize: isBold ? 15 : 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
              color: color ?? AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text(text, style: AppTextStyles.bodySmall)),
    );
  }

  // ── Actions Panel ──
  Widget _buildActionsPanel() {
    final inv = _invoice!;
    final status = inv.status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Actions'.toUpperCase(),
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5),
        ),
        const SizedBox(height: 12),
        _actionBtn(
          label: 'Edit',
          icon: Icons.edit_outlined,
          onTap: _edit,
          color: AppColors.brandNavy,
        ),
        const SizedBox(height: 6),
        _actionBtn(
          label: 'Print',
          icon: Icons.print_outlined,
          onTap: _print,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 6),
        _actionBtn(
          label: 'Share',
          icon: Icons.share_outlined,
          onTap: _share,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 6),
        _actionBtn(
          label: 'Duplicate',
          icon: Icons.copy_outlined,
          onTap: _duplicate,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        // Status-specific actions
        if (status == 'DRAFT') ...[
          _actionBtn(
            label: 'Finalize & Post',
            icon: Icons.lock_outline,
            onTap: _finalizeInvoice,
            color: AppColors.goldAccent,
            bgColor: AppColors.brandNavy,
            isPrimary: true,
          ),
          const SizedBox(height: 6),
          _actionBtn(
            label: 'Delete Draft',
            icon: Icons.delete_outline,
            onTap: _deleteInvoice,
            color: AppColors.error,
          ),
        ],
        if (status == 'SENT' || status == 'PARTIALLY_PAID') ...[
          _actionBtn(
            label: 'Receive Payment',
            icon: Icons.payment,
            onTap: _showRecordPaymentDialog,
            color: AppColors.textWhite,
            bgColor: AppColors.brandNavy,
            isPrimary: true,
          ),
          const SizedBox(height: 6),
          _actionBtn(
            label: 'Cancel Invoice',
            icon: Icons.cancel_outlined,
            onTap: _cancelInvoice,
            color: AppColors.error,
          ),
        ],
        if (status == 'PAID') ...[
          _actionBtn(
            label: 'Cancel Invoice',
            icon: Icons.cancel_outlined,
            onTap: _cancelInvoice,
            color: AppColors.error,
          ),
        ],
      ],
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
    Color? bgColor,
    bool isPrimary = false,
  }) {
    return Material(
      color: bgColor ?? Colors.transparent,
      borderRadius: AppRadius.button,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.button,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: AppRadius.button,
            border: bgColor == null ? Border.all(color: AppColors.border) : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Actions ──
  void _edit() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceFormView(editInvoice: _invoice)),
    ).then((_) => _fetchDetail());
  }

  void _share() {
    PrintShareHelper.showShareSheet(
      context,
      docLabel: 'Invoice',
      docNumber: _invoice!.invoiceNumber,
      docType: 'invoices',
      docId: _invoice!.id,
    );
  }

  void _print() {
    PrintShareHelper.showShareSheet(
      context,
      docLabel: 'Invoice',
      docNumber: _invoice!.invoiceNumber,
      docType: 'invoices',
      docId: _invoice!.id,
    );
  }

  void _duplicate() async {
    // Simple duplicate by opening form with current data
    final dup = InvoiceModel(
      id: '',
      contactId: _invoice!.contactId,
      contactName: _invoice!.contactName,
      invoiceNumber: '',
      issueDate: _invoice!.issueDate,
      dueDate: _invoice!.dueDate,
      posStateCode: _invoice!.posStateCode,
      status: 'DRAFT',
      subtotal: _invoice!.subtotal,
      discountTotal: _invoice!.discountTotal,
      cgstAmount: _invoice!.cgstAmount,
      sgstAmount: _invoice!.sgstAmount,
      igstAmount: _invoice!.igstAmount,
      roundOff: _invoice!.roundOff,
      total: _invoice!.total,
      amountPaid: 0,
      irn: null,
      qrCode: null,
      eInvoiceStatus: 'PENDING',
      eInvoiceError: null,
      lines: _invoice!.lines,
      contact: _invoice!.contact,
      notes: _invoice!.notes,
      billingAddress: _invoice!.billingAddress,
      shippingAddress: _invoice!.shippingAddress,
      utgstAmount: _invoice!.utgstAmount,
      cessAmount: _invoice!.cessAmount,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceFormView(editInvoice: dup)),
    ).then((_) => _fetchDetail());
  }

  void _deleteInvoice() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Delete Draft Invoice?',
      message: 'Are you sure you want to permanently delete this draft invoice?',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<InvoiceProvider>();
      final success = await provider.deleteInvoice(widget.invoiceId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) Navigator.pop(context);
      }
    }
  }

  void _finalizeInvoice() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Finalize Invoice?',
      message: 'This will lock the invoice and generate journal postings. You cannot edit it after finalizing.',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<InvoiceProvider>();
      final success = await provider.finalizeInvoice(widget.invoiceId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) _fetchDetail();
      }
    }
  }

  void _cancelInvoice() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel Invoice?',
      message: 'Are you sure you want to cancel this invoice? This will post reversals.',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<InvoiceProvider>();
      final success = await provider.cancelInvoice(widget.invoiceId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) _fetchDetail();
      }
    }
  }

  void _showRecordPaymentDialog() {
    final remaining = _invoice!.total - _invoice!.amountPaid;
    final amountCtrl = TextEditingController(text: remaining.toStringAsFixed(2));
    final refCtrl = TextEditingController();
    String mode = 'BANK';
    DateTime payDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final formattedDate = '${payDate.year}-${payDate.month.toString().padLeft(2, '0')}-${payDate.day.toString().padLeft(2, '0')}';
            return AlertDialog(
              title: const Text('Record Payment'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹)',
                        prefixIcon: Icon(Icons.currency_rupee_outlined, size: 16),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: payDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) setDialogState(() => payDate = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Payment Date',
                          prefixIcon: Icon(Icons.calendar_today_outlined, size: 16),
                          suffixIcon: Icon(Icons.arrow_drop_down, size: 18),
                        ),
                        child: Text(formattedDate, style: AppTextStyles.body),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: mode,
                      decoration: const InputDecoration(labelText: 'Payment Mode'),
                      items: const [
                        DropdownMenuItem(value: 'BANK', child: Text('Bank Transfer / Cheque')),
                        DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                        DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                        DropdownMenuItem(value: 'POS', child: Text('Card / POS')),
                        DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                      ],
                      onChanged: (val) { if (val != null) setDialogState(() => mode = val); },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: refCtrl,
                      decoration: const InputDecoration(labelText: 'Reference Number'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
                TextButton(
                  onPressed: () async {
                    final amt = double.tryParse(amountCtrl.text) ?? 0.0;
                    if (amt <= 0) {
                      AppToast.info(context, 'Please enter a valid amount');
                      return;
                    }
                    Navigator.pop(context);
                    setState(() => _isLoading = true);
                    final formattedPayDate = '${payDate.year}-${payDate.month.toString().padLeft(2, '0')}-${payDate.day.toString().padLeft(2, '0')}';
                    final randSeq = 1000 + (DateTime.now().millisecondsSinceEpoch % 9000);
                    final payload = {
                      'contact_id': _invoice!.contactId,
                      'payment_number': 'PAY/${payDate.year}-${(payDate.year + 1) % 100}/$randSeq',
                      'payment_date': formattedPayDate,
                      'payment_mode': mode,
                      'amount': amt,
                      if (refCtrl.text.isNotEmpty) 'reference_number': refCtrl.text,
                      'description': 'Payment for invoice ${_invoice!.invoiceNumber}',
                      'allocations': [{'invoice_id': widget.invoiceId, 'amount': amt}]
                    };
                    final provider = context.read<InvoiceProvider>();
                    final success = await provider.recordPayment(widget.invoiceId, payload);
                    if (mounted) {
                      setState(() => _isLoading = false);
                      if (success) _fetchDetail();
                    }
                  },
                  child: const Text('SAVE'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
