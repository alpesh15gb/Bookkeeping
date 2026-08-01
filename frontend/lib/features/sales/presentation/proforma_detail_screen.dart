import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:apexbooks/core/dialogs/dialog_service.dart';
import 'package:apexbooks/core/download/download_service.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/permissions/permissions.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/utils/formatters.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/widgets/transaction_detail_layout.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../models/invoice_line.dart';
import 'invoice_form_screen.dart';
import 'proforma_form_screen.dart';
import 'proforma_list_screen.dart';

final proformaDetailProvider = FutureProvider.autoDispose
    .family<_ProformaDocument, String>((ref, id) async {
      final response = await ref
          .watch(apiClientProvider)
          .get('/proforma-invoices/$id');
      return _ProformaDocument.fromJson(response.data as Map<String, dynamic>);
    });

class ProformaDetailScreen extends ConsumerStatefulWidget {
  const ProformaDetailScreen({
    super.key,
    required this.proformaId,
    this.embedded = false,
    this.onClose,
  });

  final String proformaId;
  final bool embedded;
  final VoidCallback? onClose;

  @override
  ConsumerState<ProformaDetailScreen> createState() =>
      _ProformaDetailScreenState();
}

class _ProformaDetailScreenState extends ConsumerState<ProformaDetailScreen> {
  bool _operating = false;

  Future<void> _run(
    _ProformaDocument document,
    String endpoint,
    String success, {
    bool destructive = false,
  }) async {
    if (destructive) {
      final confirmed = await const DialogService().confirm(
        context,
        title: 'Cancel ${document.number}?',
        message:
            'The quotation will remain in history but can no longer be converted.',
        confirmLabel: 'Cancel quotation',
        destructive: true,
      );
      if (!confirmed) return;
    }
    setState(() => _operating = true);
    try {
      final response = await ref
          .read(apiClientProvider)
          .post('/proforma-invoices/${document.id}/$endpoint');
      if (!mounted) return;
      final updated = _ProformaDocument.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
      ref.invalidate(proformaDetailProvider(widget.proformaId));
      ref.invalidate(proformaListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      if (endpoint == 'convert' && updated.convertedInvoiceId != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                InvoiceFormScreen(editId: updated.convertedInvoiceId),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _edit(_ProformaDocument document) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProformaFormScreen(editId: document.id),
      ),
    );
    ref.invalidate(proformaDetailProvider(widget.proformaId));
    ref.invalidate(proformaListProvider);
  }

  Future<void> _print(_ProformaDocument document) async {
    final result = await ref
        .read(downloadServiceProvider)
        .download(
          relativeUrl: '/proforma-invoices/${document.id}/print',
          filename: 'Estimate_${document.number}',
          kind: ExportKind.pdf,
        );
    if (!mounted) return;
    final message = switch (result) {
      Success() => 'Estimate PDF saved.',
      Failure(:final error) => 'Unable to create PDF: ${error.message}',
      _ => 'Unable to create PDF.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final asyncDocument = ref.watch(proformaDetailProvider(widget.proformaId));
    return asyncDocument.when(
      loading: () => const Center(child: LoadingSpinner()),
      error: (error, _) => ErrorView(
        message: userFacingErrorMessage(error),
        onRetry: () =>
            ref.invalidate(proformaDetailProvider(widget.proformaId)),
      ),
      data: (document) {
        final colors = apexColors(context);
        final fmt = ref.watch(numberFormatterProvider);
        return TransactionDetailLayout(
          title: document.number,
          embedded: widget.embedded,
          onClose: widget.onClose,
          header: _header(document, colors, fmt),
          lines: _lines(document, colors, fmt),
          totals: _totals(document, colors, fmt),
          actions: _actions(document, colors),
        );
      },
    );
  }

  List<Widget> _actions(_ProformaDocument d, ApexColors colors) => [
    if (d.status == 'DRAFT')
      PermissionGate(
        permission: Permissions.invoiceUpdate,
        child: OutlinedButton.icon(
          onPressed: _operating ? null : () => _edit(d),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit'),
        ),
      ),
    OutlinedButton.icon(
      onPressed: _operating ? null : () => _print(d),
      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
      label: const Text('PDF'),
    ),
    if (d.status == 'DRAFT')
      PermissionGate(
        permission: Permissions.invoiceFinalize,
        child: FilledButton.icon(
          onPressed: _operating
              ? null
              : () => _run(d, 'issue', 'Quotation issued.'),
          icon: const Icon(Icons.send_outlined, size: 18),
          label: const Text('Issue'),
        ),
      ),
    if (d.status == 'ISSUED') ...[
      PermissionGate(
        permission: Permissions.salesConvert,
        child: FilledButton.icon(
          onPressed: _operating
              ? null
              : () => _run(d, 'convert', 'Draft invoice created for review.'),
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('Create invoice'),
        ),
      ),
      PermissionGate(
        permission: Permissions.salesConvert,
        child: OutlinedButton.icon(
          onPressed: _operating
              ? null
              : () => _run(
                  d,
                  'convert-to-sales-order',
                  'Draft sales order created.',
                ),
          icon: const Icon(Icons.shopping_cart_outlined, size: 18),
          label: const Text('Sales order'),
        ),
      ),
    ],
    if (d.status == 'DRAFT' || d.status == 'ISSUED')
      PermissionGate(
        permission: Permissions.invoiceFinalize,
        child: IconButton(
          tooltip: 'Cancel quotation',
          onPressed: _operating
              ? null
              : () => _run(
                  d,
                  'cancel',
                  'Quotation cancelled.',
                  destructive: true,
                ),
          icon: Icon(Icons.cancel_outlined, color: colors.danger),
        ),
      ),
    StatusBadge(label: d.status, tone: toneForStatus(d.status)),
    if (_operating) const LoadingSpinner(size: 18),
  ];

  Widget _header(_ProformaDocument d, ApexColors colors, NumberFormatter fmt) =>
      Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CUSTOMER', style: _label(colors)),
                  const SizedBox(height: 4),
                  Text(
                    d.contactName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Place of supply: ${d.posStateCode}',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Issued ${d.issueDate}',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                Text(
                  'Valid until ${d.dueDate}',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  fmt.currency(d.total),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _lines(
    _ProformaDocument d,
    ApexColors colors,
    NumberFormatter fmt,
  ) => Column(
    children: d.lines
        .map(
          (line) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.productName ?? line.description ?? 'Item',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${fmt.quantity(line.quantity)} × ${fmt.currency(line.rate)} · GST ${line.gstRate.toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 11, color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
                Text(
                  fmt.currency(line.total),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        )
        .toList(),
  );

  Widget _totals(_ProformaDocument d, ApexColors colors, NumberFormatter fmt) =>
      Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: ApexCard(
            child: Column(
              children: [
                _totalRow('Subtotal', fmt.currency(d.subtotal), colors),
                if (d.discountTotal != 0)
                  _totalRow(
                    'Discount',
                    '- ${fmt.currency(d.discountTotal)}',
                    colors,
                  ),
                if (d.totalTax != 0)
                  _totalRow('GST', fmt.currency(d.totalTax), colors),
                const Divider(),
                _totalRow(
                  'Estimate total',
                  fmt.currency(d.total),
                  colors,
                  strong: true,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _totalRow(
    String label,
    String value,
    ApexColors colors, {
    bool strong = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            color: colors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            color: strong ? colors.primary : colors.textPrimary,
          ),
        ),
      ],
    ),
  );

  TextStyle _label(ApexColors colors) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: .5,
    color: colors.textMuted,
  );
}

class _ProformaDocument {
  const _ProformaDocument({
    required this.id,
    required this.number,
    required this.status,
    required this.contactName,
    required this.issueDate,
    required this.dueDate,
    required this.posStateCode,
    required this.subtotal,
    required this.discountTotal,
    required this.totalTax,
    required this.total,
    required this.lines,
    this.convertedInvoiceId,
  });

  final String id,
      number,
      status,
      contactName,
      issueDate,
      dueDate,
      posStateCode;
  final double subtotal, discountTotal, totalTax, total;
  final List<InvoiceLine> lines;
  final String? convertedInvoiceId;

  factory _ProformaDocument.fromJson(Map<String, dynamic> json) {
    final contact = json['contact'] is Map
        ? (json['contact'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return _ProformaDocument(
      id: (json['id'] ?? '').toString(),
      number: json['proforma_number']?.toString() ?? '',
      status: json['status']?.toString() ?? 'DRAFT',
      contactName: contact['name']?.toString() ?? 'Customer',
      issueDate: json['issue_date']?.toString() ?? '',
      dueDate: json['due_date']?.toString() ?? '',
      posStateCode: json['pos_state_code']?.toString() ?? '',
      subtotal: parseDoubleSafe(json['subtotal']),
      discountTotal: parseDoubleSafe(json['discount_total']),
      totalTax:
          parseDoubleSafe(json['cgst_amount']) +
          parseDoubleSafe(json['sgst_amount']) +
          parseDoubleSafe(json['igst_amount']) +
          parseDoubleSafe(json['utgst_amount']) +
          parseDoubleSafe(json['cess_amount']),
      total: parseDoubleSafe(json['total']),
      convertedInvoiceId: json['converted_to_invoice_id']?.toString(),
      lines: (json['lines'] as List? ?? const [])
          .map(
            (line) =>
                InvoiceLine.fromResponse((line as Map).cast<String, dynamic>()),
          )
          .toList(),
    );
  }
}
