import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/contact_provider.dart';
import 'package:flutter_client/providers/product_provider.dart';
import 'package:flutter_client/providers/invoice_provider.dart';
import 'package:flutter_client/providers/settings_provider.dart';
import 'package:flutter_client/models/contact.dart';
import 'package:flutter_client/models/product.dart';
import 'package:flutter_client/models/invoice.dart';
import 'package:flutter_client/models/bill.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/shared/search_sheets.dart';
import 'package:flutter_client/views/invoices/widgets/quick_create_product_sheet.dart';
import 'package:flutter_client/views/invoices/widgets/quick_create_customer_sheet.dart';

// ── GST STATE NAMES ─────────────────────────────────────────────────────────
const Map<String, String> _gstStateNames = {
  '01': 'J&K (01)',
  '02': 'Himachal Pradesh (02)',
  '03': 'Punjab (03)',
  '04': 'Chandigarh (04)',
  '05': 'Uttarakhand (05)',
  '06': 'Haryana (06)',
  '07': 'Delhi (07)',
  '08': 'Rajasthan (08)',
  '09': 'Uttar Pradesh (09)',
  '10': 'Bihar (10)',
  '11': 'Sikkim (11)',
  '12': 'Arunachal Pradesh (12)',
  '13': 'Nagaland (13)',
  '14': 'Manipur (14)',
  '15': 'Mizoram (15)',
  '16': 'Tripura (16)',
  '17': 'Meghalaya (17)',
  '18': 'Assam (18)',
  '19': 'West Bengal (19)',
  '20': 'Jharkhand (20)',
  '21': 'Odisha (21)',
  '22': 'Chhattisgarh (22)',
  '23': 'Madhya Pradesh (23)',
  '24': 'Gujarat (24)',
  '25': 'Daman & Diu (25)',
  '26': 'Dadra & NH (26)',
  '27': 'Maharashtra (27)',
  '28': 'Andhra Pradesh (28)',
  '29': 'Karnataka (29)',
  '30': 'Goa (30)',
  '31': 'Lakshadweep (31)',
  '32': 'Kerala (32)',
  '33': 'Tamil Nadu (33)',
  '34': 'Puducherry (34)',
  '35': 'A&N Islands (35)',
  '36': 'Telangana (36)',
  '37': 'Andhra Pradesh (37)',
  '38': 'Ladakh (38)',
};

// ══════════════════════════════════════════════════════════════════════════════
// TRANSACTION CONFIG
// ══════════════════════════════════════════════════════════════════════════════

class TransactionConfig {
  final String title;
  final String contactLabel;
  final String contactType;
  final String? numberLabel;
  final String? numberKey;
  final bool isPurchase;
  final bool hasReferenceNo;
  final bool hasShippingAddress;
  final bool hasLinkedInvoice;
  final bool allowScanning;
  final String successMessage;

  final Future<bool> Function(
    BuildContext context,
    Map<String, dynamic> payload,
  )
  onSave;
  final Future<Map<String, dynamic>?> Function(
    BuildContext context,
    Map<String, dynamic> payload,
  )?
  onPreview;

  const TransactionConfig({
    required this.title,
    required this.contactLabel,
    required this.contactType,
    this.numberLabel,
    this.numberKey,
    this.isPurchase = false,
    this.hasReferenceNo = false,
    this.hasShippingAddress = false,
    this.hasLinkedInvoice = false,
    this.allowScanning = false,
    required this.successMessage,
    required this.onSave,
    this.onPreview,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// TRANSACTION LINE ITEM MODEL
// ══════════════════════════════════════════════════════════════════════════════

class TransactionLineItem {
  final String uid = UniqueKey().toString();
  String productId;
  String productName;
  String hsnSac;
  double quantity;
  double rate;
  double gstRate;
  double discount;
  String description;
  String unit;

  final TextEditingController qtyCtrl;
  final TextEditingController rateCtrl;
  final TextEditingController discCtrl;
  final TextEditingController gstCtrl;
  final TextEditingController hsnCtrl;
  final TextEditingController descCtrl;

  TransactionLineItem({
    required this.productId,
    required this.productName,
    this.hsnSac = '',
    this.quantity = 1,
    this.rate = 0,
    this.gstRate = 18,
    this.discount = 0,
    this.description = '',
    this.unit = 'Nos',
  }) : qtyCtrl = TextEditingController(
         text: quantity % 1 == 0
             ? quantity.toInt().toString()
             : quantity.toString(),
       ),
       rateCtrl = TextEditingController(
         text: rate == 0 ? '' : rate.toStringAsFixed(2),
       ),
       discCtrl = TextEditingController(
         text: discount == 0 ? '' : discount.toStringAsFixed(0),
       ),
       gstCtrl = TextEditingController(text: gstRate.toStringAsFixed(0)),
       hsnCtrl = TextEditingController(text: hsnSac),
       descCtrl = TextEditingController(text: description);

  void setProduct(ProductModel p, bool isPurchase) {
    productId = p.id;
    productName = p.name;
    hsnSac = p.hsnSac;
    rate = isPurchase ? p.purchasePrice : p.salesPrice;
    gstRate = p.gstRate;
    quantity = 1;
    rateCtrl.text = rate == 0 ? '' : rate.toStringAsFixed(2);
    gstCtrl.text = gstRate.toStringAsFixed(0);
    hsnCtrl.text = p.hsnSac;
    qtyCtrl.text = '1';
    discCtrl.text = '';
    discount = 0;
  }

  double get amount => quantity * rate * (1 - discount / 100);

  void dispose() {
    qtyCtrl.dispose();
    rateCtrl.dispose();
    discCtrl.dispose();
    gstCtrl.dispose();
    hsnCtrl.dispose();
    descCtrl.dispose();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TRANSACTION FORM VIEW
// ══════════════════════════════════════════════════════════════════════════════

class TransactionFormView extends StatefulWidget {
  final TransactionConfig config;
  final dynamic editEntity;
  final Map<String, dynamic>? initialData;

  const TransactionFormView({
    super.key,
    required this.config,
    this.editEntity,
    this.initialData,
  });

  @override
  State<TransactionFormView> createState() => _TransactionFormViewState();
}

class _TransactionFormViewState extends State<TransactionFormView> {
  final _formKey = GlobalKey<FormState>();

  ContactModel? _selectedContact;
  late TextEditingController _issueDateCtrl;
  late TextEditingController _dueDateCtrl;
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _poNumberCtrl = TextEditingController();
  final TextEditingController _shippingAddrCtrl = TextEditingController();
  final TextEditingController _invoiceNoCtrl = TextEditingController();
  String? _selectedInvoiceId;
  String _posStateCode = '27';
  bool _isSaving = false;
  bool _isScanning = false;
  Timer? _previewDebounce;
  bool _isPreviewLoading = false;
  String? _nextNumberPlaceholder;
  double _amountPaid = 0;

  String? get _resolvedDocumentType {
    final key = widget.config.numberKey;
    if (key == 'invoice_number') return 'INVOICE';
    if (key == 'bill_number') return 'BILL';
    if (key == 'credit_note_number') return 'CREDIT_NOTE';
    if (key == 'debit_note_number') return 'DEBIT_NOTE';
    if (key == 'return_number') {
      return widget.config.isPurchase ? 'PURCHASE_RETURN' : 'SALES_RETURN';
    }
    return null;
  }

  Future<void> _loadNumberingSeries() async {
    if (widget.editEntity != null) return;
    try {
      final provider = context.read<SettingsProvider>();
      if (provider.numberingSeries.isEmpty) {
        await provider.fetchNumberingSeries();
      }
      final docType = _resolvedDocumentType;
      if (docType != null && provider.numberingSeries.isNotEmpty) {
        final match = provider.numberingSeries.firstWhere(
          (s) => s['document_type'] == docType && s['is_active'] == true,
          orElse: () => null,
        );
        if (match != null) {
          final prefix = match['prefix'] ?? '';
          final nextNum = match['next_number'] ?? 1;
          final suffix = match['suffix'] ?? '';
          final padding = match['padding_digits'] ?? 4;
          setState(() {
            _nextNumberPlaceholder =
                '$prefix${nextNum.toString().padLeft(padding, '0')}$suffix';
          });
        }
      }
    } catch (_) {}
  }

  final List<TransactionLineItem> _lines = [];

  // Summary computed values
  double _subtotal = 0;
  double _discountTotal = 0;
  double _cgst = 0;
  double _sgst = 0;
  double _igst = 0;
  double _utgst = 0;
  double _cess = 0;
  double _roundOff = 0;
  double _total = 0;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _issueDateCtrl = TextEditingController(
      text:
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    );
    final due = now.add(const Duration(days: 30));
    _dueDateCtrl = TextEditingController(
      text:
          '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}',
    );
    _invoiceNoCtrl.text = '';

    _parseEditEntity();

    Future.microtask(() async {
      if (!mounted) return;
      // Parallelize contacts + products fetch (saves 200-500ms)
      await Future.wait([
        context.read<ContactProvider>().fetchContacts(),
        context.read<ProductProvider>().fetchProducts(),
      ]);
      await _loadNumberingSeries();
      if (widget.config.hasLinkedInvoice) {
        await context.read<InvoiceProvider>().fetchInvoices();
      }
      _matchContactFromEntity();
      if (widget.initialData != null) {
        _applyInitialData(widget.initialData!);
      }
      _triggerPreview();
    });
  }

  void _parseEditEntity() {
    if (widget.editEntity == null) return;

    final entity = widget.editEntity;
    if (entity is InvoiceModel) {
      _amountPaid = entity.amountPaid;
      _issueDateCtrl.text = entity.issueDate;
      _dueDateCtrl.text = entity.dueDate;
      _notesCtrl.text = entity.notes ?? '';
      _posStateCode = _gstStateNames.containsKey(entity.posStateCode)
          ? entity.posStateCode
          : '27';
      _invoiceNoCtrl.text = entity.invoiceNumber;
      if (entity.shippingAddress != null &&
          entity.shippingAddress!.isNotEmpty) {
        _shippingAddrCtrl.text = _flattenAddress(entity.shippingAddress!);
      }
      for (final line in entity.lines) {
        final lineGross = line.quantity * line.rate;
        _lines.add(
          TransactionLineItem(
            productId: line.productId,
            productName: line.productName ?? 'Product',
            hsnSac: line.hsnSac,
            quantity: line.quantity,
            rate: line.rate,
            gstRate: line.gstRate,
            discount: lineGross == 0 ? 0 : (line.discount / lineGross * 100),
            description: '',
          ),
        );
      }
    } else if (entity is BillModel) {
      _amountPaid = entity.amountPaid;
      _issueDateCtrl.text = entity.billDate;
      _dueDateCtrl.text = entity.dueDate;
      _invoiceNoCtrl.text = entity.billNumber;
      _posStateCode =
          (entity.contact != null &&
              _gstStateNames.containsKey(entity.contact!.stateCode))
          ? entity.contact!.stateCode
          : '27';
      for (final line in entity.lines) {
        final lineGross = line.quantity * line.rate;
        _lines.add(
          TransactionLineItem(
            productId: line.productId,
            productName: line.productName ?? 'Product',
            hsnSac: line.hsnSac,
            quantity: line.quantity,
            rate: line.rate,
            gstRate: line.gstRate,
            discount: lineGross == 0 ? 0 : (line.discount / lineGross * 100),
            description: '',
          ),
        );
      }
    } else if (entity is Map<String, dynamic>) {
      _amountPaid = double.tryParse('${entity['amount_paid'] ?? 0}') ?? 0;
      _selectedInvoiceId = entity['invoice_id']?.toString();
      _issueDateCtrl.text = entity['issue_date'] ?? _issueDateCtrl.text;
      _dueDateCtrl.text = entity['due_date'] ?? _dueDateCtrl.text;
      _notesCtrl.text = entity['notes'] ?? '';
      _reasonCtrl.text = entity['reason'] ?? '';
      final psc = entity['pos_state_code']?.toString();
      _posStateCode = _gstStateNames.containsKey(psc) ? psc! : '27';
      _invoiceNoCtrl.text =
          entity['invoice_number'] ??
          entity['bill_number'] ??
          entity['credit_note_number'] ??
          entity['debit_note_number'] ??
          entity['return_number'] ??
          '';

      final list =
          entity['lines'] is List ? entity['lines'] as List : (entity['line_items'] is List ? entity['line_items'] as List : []);
      for (final item in list) {
        _lines.add(
          TransactionLineItem(
            productId: item['product_id'] ?? '',
            productName: item['product_name'] ?? 'Product',
            hsnSac: item['hsn_sac'] ?? '',
            quantity:
                double.tryParse((item['quantity'] ?? 0).toString()) ?? 1.0,
            rate: double.tryParse((item['rate'] ?? 0).toString()) ?? 0.0,
            gstRate:
                double.tryParse((item['gst_rate'] ?? 0.0).toString()) ?? 0.0,
            discount:
                double.tryParse((item['discount'] ?? 0.0).toString()) ?? 0.0,
            description: item['description'] ?? '',
          ),
        );
      }
    }
  }

  void _matchContactFromEntity() {
    if (widget.editEntity == null) return;
    final contacts = context.read<ContactProvider>().contacts;
    String? contactId;
    if (widget.editEntity is InvoiceModel)
      contactId = widget.editEntity.contactId;
    if (widget.editEntity is BillModel) contactId = widget.editEntity.contactId;
    if (widget.editEntity is Map)
      contactId = widget.editEntity['contact_id']?.toString();

    if (contactId != null) {
      final match = contacts.where((c) => c.id == contactId);
      if (match.isNotEmpty) {
        setState(() {
          _selectedContact = match.first;
          _posStateCode =
              _gstStateNames.containsKey(_selectedContact!.stateCode)
              ? _selectedContact!.stateCode
              : '27';
        });
      }
    }
  }

  final TextEditingController _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _issueDateCtrl.dispose();
    _dueDateCtrl.dispose();
    _notesCtrl.dispose();
    _poNumberCtrl.dispose();
    _shippingAddrCtrl.dispose();
    _invoiceNoCtrl.dispose();
    _reasonCtrl.dispose();
    _previewDebounce?.cancel();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  String _flattenAddress(Map<String, dynamic> addr) {
    return [
      addr['line1'],
      addr['line2'],
      addr['city'],
      addr['state'],
      addr['pincode'],
    ].where((v) => v != null && v.toString().isNotEmpty).join(', ');
  }

  void _applyInitialData(Map<String, dynamic> data) {
    final contactId = data['contact_id']?.toString();
    if (contactId != null) {
      final matches = context.read<ContactProvider>().contacts.where(
        (c) => c.id == contactId,
      );
      if (matches.isNotEmpty) {
        _selectedContact = matches.first;
        _posStateCode = _gstStateNames.containsKey(_selectedContact!.stateCode)
            ? _selectedContact!.stateCode
            : '27';
      }
    }
    if (data['pos_state_code'] != null) {
      final psc = data['pos_state_code'].toString();
      _posStateCode = _gstStateNames.containsKey(psc) ? psc : '27';
    }
    final reference =
        data['reference_number'] ??
        data['po_number'] ??
        data['so_number'] ??
        data['challan_number'];
    if (reference != null) _poNumberCtrl.text = reference.toString();
    if (data['notes'] != null) _notesCtrl.text = data['notes'].toString();

    final rawLines = data['lines'] ?? data['line_items'];
    if (rawLines is List) {
      _lines.clear();
      for (final rawLine in rawLines) {
        if (rawLine is! Map) continue;
        final qty =
            double.tryParse((rawLine['quantity'] ?? 1).toString()) ?? 1.0;
        final rate = double.tryParse((rawLine['rate'] ?? 0).toString()) ?? 0.0;
        final disc =
            double.tryParse((rawLine['discount'] ?? 0).toString()) ?? 0.0;
        _lines.add(
          TransactionLineItem(
            productId: rawLine['product_id']?.toString() ?? '',
            productName:
                rawLine['product_name']?.toString() ??
                rawLine['description']?.toString() ??
                'Product',
            hsnSac: rawLine['hsn_sac']?.toString() ?? '',
            quantity: qty,
            rate: rate,
            gstRate:
                double.tryParse((rawLine['gst_rate'] ?? 18.0).toString()) ??
                18.0,
            discount: disc,
            description: rawLine['description']?.toString() ?? '',
          ),
        );
      }
    }
  }

  void _triggerPreview() {
    _previewDebounce?.cancel();
    if (_lines.isEmpty) {
      setState(() {
        _subtotal = 0;
        _discountTotal = 0;
        _cgst = 0;
        _sgst = 0;
        _igst = 0;
        _utgst = 0;
        _cess = 0;
        _roundOff = 0;
        _total = 0;
        _isPreviewLoading = false;
      });
      return;
    }

    if (widget.config.onPreview == null) {
      double sub = 0;
      double disc = 0;
      double gst = 0;
      for (final l in _lines) {
        final lineGross = l.quantity * l.rate;
        final lineDisc = lineGross * (l.discount / 100);
        final lineNet = lineGross - lineDisc;
        sub += lineGross;
        disc += lineDisc;
        gst += lineNet * (l.gstRate / 100);
      }
      setState(() {
        _subtotal = sub;
        _discountTotal = disc;
        if (_posStateCode == '27' || _posStateCode == '29') {
          _cgst = gst / 2;
          _sgst = gst / 2;
          _igst = 0;
        } else {
          _cgst = 0;
          _sgst = 0;
          _igst = gst;
        }
        _roundOff = 0;
        _total = sub - disc + gst;
      });
      return;
    }

    setState(() => _isPreviewLoading = true);
    _previewDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;

      // Try server preview first; fall back to local calculation
      Map<String, dynamic>? preview;
      if (widget.config.onPreview != null) {
        final payload = _buildPayload();
        preview = await widget.config.onPreview!(context, payload);
      }

      if (mounted) {
        if (preview != null) {
          setState(() {
            _subtotal =
                double.tryParse((preview!['subtotal'] ?? 0).toString()) ?? 0;
            _discountTotal =
                double.tryParse((preview['discount_total'] ?? 0).toString()) ??
                0;
            _cgst =
                double.tryParse(
                  (preview['cgst_amount'] ?? preview['cgst'] ?? 0).toString(),
                ) ??
                0;
            _sgst =
                double.tryParse(
                  (preview['sgst_amount'] ?? preview['sgst'] ?? 0).toString(),
                ) ??
                0;
            _igst =
                double.tryParse(
                  (preview['igst_amount'] ?? preview['igst'] ?? 0).toString(),
                ) ??
                0;
            _utgst =
                double.tryParse(
                  (preview['utgst_amount'] ?? preview['utgst'] ?? 0).toString(),
                ) ??
                0;
            _cess =
                double.tryParse(
                  (preview['cess_amount'] ?? preview['cess'] ?? 0).toString(),
                ) ??
                0;
            _roundOff =
                double.tryParse((preview['round_off'] ?? 0).toString()) ?? 0;
            _total = double.tryParse((preview['total'] ?? 0).toString()) ?? 0;
            _isPreviewLoading = false;
          });
        } else {
          // Fallback: local calculation
          double sub = 0;
          double disc = 0;
          double gst = 0;
          for (final l in _lines) {
            final lineGross = l.quantity * l.rate;
            final lineDisc = lineGross * (l.discount / 100);
            final lineNet = lineGross - lineDisc;
            sub += lineGross;
            disc += lineDisc;
            gst += lineNet * (l.gstRate / 100);
          }
          setState(() {
            _subtotal = sub;
            _discountTotal = disc;
            if (_posStateCode == '27' || _posStateCode == '29') {
              _cgst = gst / 2;
              _sgst = gst / 2;
              _igst = 0;
            } else {
              _cgst = 0;
              _sgst = 0;
              _igst = gst;
            }
            _roundOff = 0;
            _total = sub - disc + gst;
            _isPreviewLoading = false;
          });
        }
      }
    });
  }

  Map<String, dynamic> _buildPayload() {
    final Map<String, dynamic> payload = {
      'issue_date': _issueDateCtrl.text,
      'due_date': _dueDateCtrl.text,
      'pos_state_code': RegExp(r'^[0-9]{2}$').hasMatch(_posStateCode)
          ? _posStateCode
          : '27',
      'notes': _notesCtrl.text.trim(),
      'line_items': _lines
          .map(
            (l) => {
              'product_id': l.productId,
              'quantity': l.quantity,
              'rate': l.rate,
              'discount': (l.quantity * l.rate * l.discount / 100)
                  .toStringAsFixed(4),
              'hsn_sac': RegExp(r'^[0-9]{4,8}$').hasMatch(l.hsnSac)
                  ? l.hsnSac
                  : '84716050',
              'gst_rate': l.gstRate,
              if (l.descCtrl.text.trim().isNotEmpty)
                'description': l.descCtrl.text.trim(),
            },
          )
          .toList(),
    };

    if (_selectedContact != null) {
      payload['contact_id'] = _selectedContact!.id;
    }
    if (_poNumberCtrl.text.trim().isNotEmpty) {
      payload['reference_number'] = _poNumberCtrl.text.trim();
    }
    if (_shippingAddrCtrl.text.trim().isNotEmpty) {
      payload['shipping_address'] = {
        'address_2': _shippingAddrCtrl.text.trim(),
      };
    }
    if (_selectedInvoiceId != null) {
      payload['invoice_id'] = _selectedInvoiceId;
    }
    if (_reasonCtrl.text.trim().isNotEmpty) {
      payload['reason'] = _reasonCtrl.text.trim();
    }

    if (widget.config.numberKey != null) {
      final key = widget.config.numberKey!;
      payload[key] = _invoiceNoCtrl.text.trim();
    }

    return payload;
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date != null && mounted) {
      setState(() {
        ctrl.text =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      });
      _triggerPreview();
    }
  }

  void _onContactSelected(ContactModel c) {
    setState(() {
      _selectedContact = c;
      _posStateCode = _gstStateNames.containsKey(c.stateCode)
          ? c.stateCode
          : '27';
      if (c.shippingAddress != null && c.shippingAddress!.isNotEmpty) {
        _shippingAddrCtrl.text = _flattenAddress(c.shippingAddress!);
      }
    });
    _triggerPreview();
  }

  void _addEmptyLine() {
    setState(() {
      _lines.add(
        TransactionLineItem(
          productId: '',
          productName: '',
          quantity: 1,
          rate: 0,
          gstRate: 18,
        ),
      );
    });
  }

  void _setLineProduct(int index, ProductModel p) {
    setState(() {
      _lines[index].setProduct(p, widget.config.isPurchase);
    });
    _triggerPreview();
  }

  void _removeLine(int index) {
    setState(() {
      _lines[index].dispose();
      _lines.removeAt(index);
    });
    _triggerPreview();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedContact == null && !widget.config.hasLinkedInvoice) {
      _showSnack('Please select a contact', error: true);
      return;
    }
    if (_lines.isEmpty) {
      _showSnack('Add at least one line item', error: true);
      return;
    }
    if (_lines.any((l) => l.productId.isEmpty)) {
      _showSnack('Select a product for every line item', error: true);
      return;
    }
    if (_lines.any((l) => l.quantity <= 0)) {
      _showSnack(
        'Quantity must be greater than 0 for all line items',
        error: true,
      );
      return;
    }

    setState(() => _isSaving = true);
    final payload = _buildPayload();
    final success = await widget.config.onSave(context, payload);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        _showSnack(widget.config.successMessage);
        Navigator.pop(context, true);
      }
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  Future<void> _openContactSearch() async {
    final allContacts = context.read<ContactProvider>().contacts;
    final filtered = widget.config.contactType == 'CUSTOMER'
        ? allContacts
              .where(
                (c) =>
                    c.contactType.toUpperCase() == 'CUSTOMER' ||
                    c.contactType.toUpperCase() == 'BOTH',
              )
              .toList()
        : widget.config.contactType == 'VENDOR'
        ? allContacts
              .where(
                (c) =>
                    c.contactType.toUpperCase() == 'VENDOR' ||
                    c.contactType.toUpperCase() == 'BOTH',
              )
              .toList()
        : allContacts;

    final selected = await showModalBottomSheet<ContactModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => ContactSearchSheet(
        contacts: filtered,
        title: 'Select ${widget.config.contactLabel}',
        onCreateNew: (name) async {
          Navigator.pop(context);
          final created = await showQuickCreateCustomer(
            context,
            initialName: name,
            contactType: widget.config.contactType,
          );
          if (created != null && mounted) _onContactSelected(created);
        },
      ),
    );
    if (selected != null && mounted) _onContactSelected(selected);
  }

  Future<void> _openProductSearch(int lineIndex) async {
    final products = context.read<ProductProvider>().products;
    final selected = await showModalBottomSheet<ProductModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => ProductSearchSheet(
        products: products,
        isPurchase: widget.config.isPurchase,
        onCreateNew: (name) async {
          Navigator.pop(context);
          final created = await showQuickCreateProduct(
            context,
            initialName: name,
          );
          if (created != null && mounted) _setLineProduct(lineIndex, created);
        },
      ),
    );
    if (selected != null && mounted) _setLineProduct(lineIndex, selected);
  }

  Future<void> _scanBill() async {
    setState(() => _isScanning = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'tiff', 'bmp'],
        withData: true,
        dialogTitle: 'Select Bill Image or PDF',
      );

      if (result == null || result.files.isEmpty || !mounted) {
        setState(() => _isScanning = false);
        return;
      }

      final picked = result.files.first;
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showSnack('Could not read file. Please try again.', error: true);
        setState(() => _isScanning = false);
        return;
      }

      final uri = Uri.parse('${ApiClient.baseUrl}/bills/scan-image');
      final request = http.MultipartRequest('POST', uri);

      if (ApiClient.accessToken != null) {
        request.headers['Authorization'] = 'Bearer ${ApiClient.accessToken}';
      }
      if (ApiClient.tenantId != null) {
        request.headers['X-Tenant-ID'] = ApiClient.tenantId!;
      }

      request.files.add(http.MultipartFile.fromBytes(
        'file', bytes,
        filename: picked.name,
      ));
      request.fields['confidence'] = '0.25';

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _applyScannedData(data);
      } else {
        String msg = 'Scan failed (${response.statusCode})';
        try {
          final b = jsonDecode(response.body);
          if (b is Map) msg = b['detail']?.toString() ?? msg;
        } catch (_) {}
        _showSnack(msg, error: true);
      }
    } catch (e) {
      if (mounted) _showSnack('Scan error: $e', error: true);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _applyScannedData(Map<String, dynamic> data) {
    if (data['vendor_name'] != null || data['vendor_gstin'] != null) {
      final gstin = data['vendor_gstin']?.toString().toUpperCase();
      final name = data['vendor_name']?.toString().toLowerCase();
      final vendors = context.read<ContactProvider>().vendors;
      ContactModel? matched;
      if (gstin != null && gstin.isNotEmpty) {
        for (final v in vendors) {
          if (v.gstin?.toUpperCase() == gstin) {
            matched = v;
            break;
          }
        }
      }
      if (matched == null && name != null && name.isNotEmpty) {
        for (final v in vendors) {
          final vName = v.name.toLowerCase();
          if (vName.contains(name) || name.contains(vName)) {
            matched = v;
            break;
          }
        }
      }
      if (matched != null) {
        final ContactModel m = matched;
        setState(() {
          _selectedContact = m;
          if (m.stateCode.length == 2) {
            _posStateCode = m.stateCode;
          }
        });
      }
    }

    if (data['bill_number'] != null) {
      setState(() => _invoiceNoCtrl.text = data['bill_number'] as String);
    }
    if (data['bill_date'] != null) {
      setState(() => _issueDateCtrl.text = data['bill_date'] as String);
    }
    if (data['due_date'] != null) {
      setState(() => _dueDateCtrl.text = data['due_date'] as String);
    }

    final scannedLines = (data['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (scannedLines.isNotEmpty) {
      setState(() {
        _lines.removeWhere((l) => l.productId.isEmpty && l.rate == 0);

        for (final sl in scannedLines) {
          final qty = (sl['qty'] as num?)?.toDouble() ?? 1.0;
          final rate = (sl['rate'] as num?)?.toDouble() ?? 0.0;
          final gstRate = (sl['gst_rate'] as num?)?.toDouble() ?? 18.0;
          _lines.add(TransactionLineItem(
            productId: '',
            productName: sl['description']?.toString() ?? 'Item',
            hsnSac: sl['hsn']?.toString() ?? '',
            quantity: qty,
            rate: rate,
            gstRate: gstRate,
            discount: 0,
            description: sl['description']?.toString() ?? '',
          ));
        }
      });
    }

    final filledFields = <String>[];
    if (data['bill_number'] != null) filledFields.add('Bill number');
    if (data['bill_date'] != null) filledFields.add('Date');
    if (data['due_date'] != null) filledFields.add('Due date');
    if (scannedLines.isNotEmpty) filledFields.add('${scannedLines.length} line item(s)');
    if (data['vendor_name'] != null) filledFields.add('Vendor: ${data['vendor_name']}');

    final conf = ((data['overall_confidence'] as num?)?.toDouble() ?? 0.0) * 100;
    final warnings = (data['warnings'] as List?)?.cast<String>() ?? [];

    final msg = filledFields.isNotEmpty
        ? 'Scanned (${conf.toStringAsFixed(0)}% confidence): ${filledFields.join(', ')}'
        : 'Scan complete but no fields could be extracted. Please fill manually.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: filledFields.isNotEmpty ? AppColors.success : AppColors.warning,
        duration: const Duration(seconds: 4),
        action: warnings.isNotEmpty
            ? SnackBarAction(
                label: 'Details',
                textColor: Colors.white,
                onPressed: () => _showScanWarnings(warnings),
              )
            : null,
      ),
    );

    _triggerPreview();
  }

  void _showScanWarnings(List<String> warnings) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scan Notes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: warnings
              .map((w) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: AppColors.warning),
                        const SizedBox(width: 6),
                        Expanded(child: Text(w, style: AppTextStyles.bodySmall)),
                      ],
                    ),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = AdaptiveLayout.isDesktop(context);
    final isEdit = widget.editEntity != null;
    final displayTitle = isEdit
        ? 'Edit ${widget.config.title}'
        : widget.config.title;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        foregroundColor: AppColors.brandNavy,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          displayTitle,
          style: AppTextStyles.h3.copyWith(color: AppColors.brandNavy),
        ),
        actions: [
          if (_isPreviewLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (widget.config.allowScanning)
            IconButton(
              icon: _isScanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.brandNavy,
                      ),
                    )
                  : const Icon(Icons.document_scanner_outlined, size: 20),
              tooltip: 'Scan vendor bill',
              onPressed: _isScanning || _isSaving ? null : _scanBill,
            ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ElevatedButton(
              onPressed: _isSaving || _isPreviewLoading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Doc Info Row (Invoice Number, Date, State)
              _buildDocInfoCard(isDesktop),
              const SizedBox(height: 16),

              // 2. Bill To & Ship To
              _buildPartiesRow(isDesktop),
              const SizedBox(height: 16),

              // 3. Line Items Table or stacked cards
              _buildLineItemsSection(isDesktop),
              const SizedBox(height: 16),

              // 4. Totals, Breakdowns, Notes
              _buildTotalsAndBreakdownSection(isDesktop),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocInfoCard(bool isDesktop) {
    if (isDesktop) {
      return AppCard(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _invoiceNoCtrl,
                decoration: InputDecoration(
                  labelText: widget.config.numberLabel ?? 'Document Number',
                  prefixIcon: const Icon(Icons.tag, size: 16),
                  hintText: _nextNumberPlaceholder ?? 'Auto-generated',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _DateField(
                ctrl: _issueDateCtrl,
                label: widget.config.isPurchase ? 'Bill Date *' : 'Invoice Date *',
                onTap: () => _pickDate(_issueDateCtrl),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _posStateCode,
                decoration: const InputDecoration(
                  labelText: 'Place of Supply (State) *',
                  prefixIcon: Icon(Icons.map_outlined, size: 16),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                items: _gstStateNames.entries
                    .map(
                      (e) => DropdownMenuItem<String>(
                        value: e.key,
                        child: Text(e.value),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _posStateCode = val);
                    _triggerPreview();
                  }
                },
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextFormField(
            controller: _invoiceNoCtrl,
            decoration: InputDecoration(
              labelText: widget.config.numberLabel ?? 'Document Number',
              prefixIcon: const Icon(Icons.tag, size: 16),
              hintText: _nextNumberPlaceholder ?? 'Auto-generated',
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
          ),
          const SizedBox(height: 12),
          _DateField(
            ctrl: _issueDateCtrl,
            label: widget.config.isPurchase ? 'Bill Date *' : 'Invoice Date *',
            onTap: () => _pickDate(_issueDateCtrl),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _posStateCode,
            decoration: const InputDecoration(
              labelText: 'Place of Supply (State) *',
              prefixIcon: Icon(Icons.map_outlined, size: 16),
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            items: _gstStateNames.entries
                .map(
                  (e) => DropdownMenuItem<String>(
                    value: e.key,
                    child: Text(e.value),
                  ),
                )
                .toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _posStateCode = val);
                _triggerPreview();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPartiesRow(bool isDesktop) {
    final billToCard = AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_box_outlined,
                color: AppColors.brandNavy,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'BILL TO',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.brandNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Customer Picker
          FormField<ContactModel>(
            validator: (_) =>
                _selectedContact == null ? 'Contact is required' : null,
            builder: (state) => GestureDetector(
              onTap: _openContactSearch,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: state.hasError ? AppColors.error : AppColors.border,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedContact != null
                            ? _selectedContact!.name
                            : 'Select ${widget.config.contactLabel} *',
                        style: _selectedContact != null
                            ? AppTextStyles.bodyMedium
                            : AppTextStyles.body.copyWith(
                                color: AppColors.textMuted,
                              ),
                      ),
                    ),
                    const Icon(Icons.search, size: 16),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey(_selectedContact?.gstin),
            initialValue: _selectedContact?.gstin ?? '',
            decoration: const InputDecoration(
              labelText: 'GSTIN *',
              hintText: 'Enter GSTIN',
            ),
            readOnly: true,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey(_selectedContact?.stateCode),
            initialValue: _selectedContact != null
                ? '${_selectedContact!.stateCode}${_selectedContact!.billingAddress['state'] != null ? ' - ${_selectedContact!.billingAddress['state']}' : ''}'
                : '',
            decoration: const InputDecoration(
              labelText: 'State Code *',
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            readOnly: true,
          ),
        ],
      ),
    );

    final shipToCard = AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                color: AppColors.brandNavy,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'SHIP TO',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.brandNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _shippingAddrCtrl,
            decoration: InputDecoration(
              labelText: '${widget.config.contactLabel} Name *',
              hintText: 'e.g. Warehouse address',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey(_selectedContact?.gstin),
            initialValue: _selectedContact?.gstin ?? '',
            decoration: const InputDecoration(
              labelText: 'GSTIN',
              hintText: 'Enter GSTIN',
            ),
            readOnly: true,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey(_selectedContact?.stateCode),
            initialValue: _selectedContact != null
                ? '${_selectedContact!.stateCode}${_selectedContact!.billingAddress['state'] != null ? ' - ${_selectedContact!.billingAddress['state']}' : ''}'
                : '',
            decoration: const InputDecoration(
              labelText: 'State Code *',
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            readOnly: true,
          ),
        ],
      ),
    );

    if (isDesktop) {
      return Row(
        children: [
          Expanded(child: billToCard),
          const SizedBox(width: 16),
          Expanded(child: shipToCard),
        ],
      );
    }
    return Column(
      children: [billToCard, const SizedBox(height: 16), shipToCard],
    );
  }

  Widget _buildLineItemsSection(bool isDesktop) {
    if (!isDesktop) {
      return Column(
        children:
            _lines
                .asMap()
                .entries
                .map((e) => _buildMobileLineCard(e.key, e.value))
                .toList() +
            [
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _addEmptyLine,
                icon: const Icon(Icons.add),
                label: const Text('Add Row'),
              ),
            ],
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Navy header row
          Container(
            color: AppColors.brandNavy,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: const Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    'S.No',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Product/Service Description *',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    'HSN/SAC *',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    'Qty *',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    'Unit',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    'Rate (₹) *',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    'Discount %',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    'Taxable Value (₹)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    'GST Rate %',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    'GST Amount (₹)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(width: 40),
              ],
            ),
          ),
          if (_lines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No items added yet',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _lines.length,
              itemBuilder: (context, index) {
                final line = _lines[index];
                final taxableValue =
                    line.quantity * line.rate * (1 - line.discount / 100);
                final gstAmount = taxableValue * (line.gstRate / 100);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: GestureDetector(
                          onTap: () => _openProductSearch(index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              line.productId.isNotEmpty
                                  ? line.productName
                                  : 'Select product...',
                              style: TextStyle(
                                color: line.productId.isNotEmpty
                                    ? Colors.black
                                    : AppColors.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: line.hsnCtrl,
                          onChanged: (v) => line.hsnSac = v,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.all(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: line.qtyCtrl,
                          textAlign: TextAlign.center,
                          onChanged: (v) {
                            line.quantity = double.tryParse(v) ?? 1;
                            _triggerPreview();
                          },
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.all(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: DropdownButtonFormField<String>(
                          initialValue: line.unit,
                          isDense: true,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Nos', child: Text('Nos')),
                            DropdownMenuItem(value: 'Pcs', child: Text('Pcs')),
                            DropdownMenuItem(value: 'Box', child: Text('Box')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => line.unit = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: line.rateCtrl,
                          textAlign: TextAlign.right,
                          onChanged: (v) {
                            line.rate = double.tryParse(v) ?? 0;
                            _triggerPreview();
                          },
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.all(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: line.discCtrl,
                          textAlign: TextAlign.center,
                          onChanged: (v) {
                            line.discount = double.tryParse(v) ?? 0;
                            _triggerPreview();
                          },
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.all(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: Text(
                          '₹${taxableValue.toStringAsFixed(2)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: DropdownButtonFormField<String>(
                          initialValue: line.gstRate.toStringAsFixed(0),
                          isDense: true,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: '18', child: Text('18%')),
                            DropdownMenuItem(value: '12', child: Text('12%')),
                            DropdownMenuItem(value: '5', child: Text('5%')),
                            DropdownMenuItem(value: '0', child: Text('0%')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(
                                () => line.gstRate = double.tryParse(v) ?? 18,
                              );
                              _triggerPreview();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: Text(
                          '₹${gstAmount.toStringAsFixed(2)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.error,
                          ),
                          onPressed: () => _removeLine(index),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _addEmptyLine,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Row'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandNavy,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLineCard(int index, TransactionLineItem line) {
    return _LineItemCard(
      index: index,
      line: line,
      onPickProduct: () => _openProductSearch(index),
      onChanged: _triggerPreview,
      onRemove: () => _removeLine(index),
    );
  }

  Widget _buildTotalsAndBreakdownSection(bool isDesktop) {
    final leftNotesPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Amount in Words',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _total > 0
                    ? 'Rupees ${_convertToWords(_total)} Only'
                    : 'Zero Rupees Only',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandNavy,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes (Optional)',
              border: InputBorder.none,
              hintText: 'Enter notes...',
            ),
          ),
        ),
      ],
    );

    final taxBreakdownsPanel = AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TAX BREAKDOWN',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 12),
          _SummaryRow('CGST Amount', _cgst),
          _SummaryRow('SGST Amount', _sgst),
          _SummaryRow('IGST Amount', _igst),
          if (_utgst.abs() > 0.001) _SummaryRow('UTGST Amount', _utgst),
          if (_cess.abs() > 0.001) _SummaryRow('Cess Amount', _cess),
        ],
      ),
    );

    final totalSummaryCard = AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryRow('Total Taxable Value', _subtotal),
          if (_discountTotal.abs() > 0.001)
            _SummaryRow('Discount', -_discountTotal, color: AppColors.success),
          _SummaryRow(
            'Total Tax Amount',
            _cgst + _sgst + _igst + _utgst + _cess,
          ),
          if (_roundOff.abs() > 0.001) _SummaryRow('Round Off', _roundOff),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Invoice Amount',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                '₹${_total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: AppColors.brandNavy,
                ),
              ),
            ],
          ),
          if (_amountPaid > 0) ...[
            const SizedBox(height: 8),
            _SummaryRow('Amount Paid', _amountPaid, color: AppColors.success),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Balance Due',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.error),
                ),
                Text(
                  '₹${(_total - _amountPaid).clamp(0, double.infinity).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: leftNotesPanel),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: taxBreakdownsPanel),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: totalSummaryCard),
        ],
      );
    }
    return Column(
      children: [
        leftNotesPanel,
        const SizedBox(height: 16),
        taxBreakdownsPanel,
        const SizedBox(height: 16),
        totalSummaryCard,
      ],
    );
  }

  String _convertToWords(double val) {
    // Simple helper mapping to words representation
    return '${val.toStringAsFixed(2)} Rupees';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MODULAR WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _DateField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final VoidCallback onTap;
  const _DateField({
    required this.ctrl,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      readOnly: true,
      onTap: onTap,
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
        suffixIcon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final Color? color;
  const _SummaryRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodySmall),
          Text(
            '₹${value.toStringAsFixed(2)}',
            style: AppTextStyles.numeric.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _LineItemCard extends StatefulWidget {
  final int index;
  final TransactionLineItem line;
  final VoidCallback onPickProduct;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _LineItemCard({
    super.key,
    required this.index,
    required this.line,
    required this.onPickProduct,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_LineItemCard> createState() => _LineItemCardState();
}

class _LineItemCardState extends State<_LineItemCard> {
  bool _showDetails = false;

  TransactionLineItem get line => widget.line;
  bool get _hasProduct => line.productId.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: _hasProduct
              ? AppColors.brandNavy.withValues(alpha: 0.18)
              : AppColors.border,
          width: _hasProduct ? 1.5 : 1,
        ),
        boxShadow: [
          if (_hasProduct)
            BoxShadow(
              color: AppColors.brandNavy.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            decoration: BoxDecoration(
              color: _hasProduct
                  ? AppColors.brandNavy.withValues(alpha: 0.04)
                  : AppColors.borderLight,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.drag_handle_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _hasProduct ? AppColors.brandNavy : AppColors.border,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '#${(widget.index + 1).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _showDetails = !_showDetails),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Row(
                      children: [
                        Text(
                          _showDetails ? 'Less' : 'Details',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                        Icon(
                          _showDetails
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: widget.onRemove,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: widget.onPickProduct,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _hasProduct
                          ? AppColors.brandNavy.withValues(alpha: 0.04)
                          : AppColors.bgLight,
                      border: Border.all(
                        color: _hasProduct
                            ? AppColors.brandNavy.withValues(alpha: 0.25)
                            : AppColors.border,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _hasProduct
                              ? Icons.inventory_2_outlined
                              : Icons.search_rounded,
                          size: 16,
                          color: _hasProduct
                              ? AppColors.brandNavy
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _hasProduct
                                ? line.productName
                                : 'Search or type a product name...',
                            style: _hasProduct
                                ? AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.brandNavy,
                                    fontWeight: FontWeight.w600,
                                  )
                                : AppTextStyles.body.copyWith(
                                    color: AppColors.textMuted,
                                  ),
                          ),
                        ),
                        if (_hasProduct) ...[
                          Text(
                            'change',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.swap_horiz_rounded,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _SmallField(
                      label: 'Qty',
                      ctrl: line.qtyCtrl,
                      onChanged: (v) {
                        line.quantity = double.tryParse(v) ?? 1;
                        widget.onChanged();
                      },
                    ),
                    const SizedBox(width: 8),
                    _SmallField(
                      label: 'Rate (₹)',
                      ctrl: line.rateCtrl,
                      flex: 2,
                      onChanged: (v) {
                        line.rate = double.tryParse(v) ?? 0;
                        widget.onChanged();
                      },
                    ),
                    const SizedBox(width: 8),
                    _SmallField(
                      label: 'Disc %',
                      ctrl: line.discCtrl,
                      onChanged: (v) {
                        line.discount = double.tryParse(v) ?? 0;
                        widget.onChanged();
                      },
                    ),
                    const SizedBox(width: 8),
                    _SmallField(
                      label: 'GST %',
                      ctrl: line.gstCtrl,
                      onChanged: (v) {
                        line.gstRate = double.tryParse(v) ?? 0;
                        widget.onChanged();
                      },
                    ),
                  ],
                ),
                if (_showDetails) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: line.hsnCtrl,
                          style: const TextStyle(fontSize: 12),
                          onChanged: (v) => line.hsnSac = v,
                          decoration: const InputDecoration(
                            labelText: 'HSN / SAC',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: line.descCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            labelText: 'Item Description',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _hasProduct
                          ? AppColors.brandNavy.withValues(alpha: 0.08)
                          : AppColors.borderLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Amount: ',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '₹${line.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _hasProduct
                                ? AppColors.brandNavy
                                : AppColors.textMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final Function(String) onChanged;
  final int flex;

  const _SmallField({
    required this.label,
    required this.ctrl,
    required this.onChanged,
    this.flex = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            onChanged: onChanged,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
