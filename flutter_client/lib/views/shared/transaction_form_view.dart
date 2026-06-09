import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:flutter_client/views/shared/scanned_bill_preview_dialog.dart';
import 'package:flutter_client/utils/haptic_helper.dart';
import 'package:flutter_client/views/invoices/invoice_detail_view.dart';
import 'package:flutter_client/core/print_share_helper.dart';

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
  bool _isGstInclusive = false;
  String? _scannedVendorName;
  Timer? _previewDebounce;
  bool _isPreviewLoading = false;
  String? _nextNumberPlaceholder;
  double _amountPaid = 0;
  bool _shipToSameAsBilling = true;
  bool _hasRecoveredDraft = false;
  bool _isDirty = false;

  final ScrollController _scrollController = ScrollController();

  Future<bool> _onWillPop() async {
    if (!_isDirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Are you sure you want to go back?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('STAY')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('DISCARD')),
        ],
      ),
    );
    return result ?? false;
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  void _markClean() {
    setState(() => _isDirty = false);
  }

  bool get _gstEnabled {
    try {
      return context.read<SettingsProvider>().gstEnabled;
    } catch (_) {
      return true;
    }
  }

  String get _draftKey => 'draft_${widget.config.title}_${widget.editEntity != null ? (widget.editEntity is Map ? widget.editEntity['id'] : widget.editEntity.id) : 'new'}';

  Future<void> _checkDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_draftKey);
    if (data != null && mounted) {
      setState(() {
        _hasRecoveredDraft = true;
      });
    }
  }

  Future<void> _saveDraftToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _buildPayload();
    await prefs.setString(_draftKey, jsonEncode(payload));
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  void _recoverDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_draftKey);
    if (data != null) {
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      setState(() {
        _applyInitialData(decoded);
        _hasRecoveredDraft = false;
      });
      _triggerPreview();
    }
  }

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

    _issueDateCtrl.addListener(_markDirty);
    _dueDateCtrl.addListener(_markDirty);
    _notesCtrl.addListener(_markDirty);
    _poNumberCtrl.addListener(_markDirty);
    _shippingAddrCtrl.addListener(_markDirty);
    _invoiceNoCtrl.addListener(_markDirty);
    _reasonCtrl.addListener(_markDirty);

    _parseEditEntity();
    _isDirty = false;

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
      _isDirty = false;
      await _checkDraft();
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
    if (widget.editEntity is InvoiceModel) {
      contactId = widget.editEntity.contactId;
    }
    if (widget.editEntity is BillModel) {
      contactId = widget.editEntity.contactId;
    }
    if (widget.editEntity is Map) {
      contactId = widget.editEntity['contact_id']?.toString();
    }

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
    _issueDateCtrl.removeListener(_markDirty);
    _dueDateCtrl.removeListener(_markDirty);
    _notesCtrl.removeListener(_markDirty);
    _poNumberCtrl.removeListener(_markDirty);
    _shippingAddrCtrl.removeListener(_markDirty);
    _invoiceNoCtrl.removeListener(_markDirty);
    _reasonCtrl.removeListener(_markDirty);
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
    _scrollController.dispose();
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
    _saveDraftToDisk();
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
        if (_isGstInclusive) {
          final double rateExcl = l.rate / (1 + l.gstRate / 100);
          final double grossExcl = l.quantity * rateExcl;
          final double discExcl = grossExcl * (l.discount / 100);
          final double netExcl = grossExcl - discExcl;
          sub += grossExcl;
          disc += discExcl;
          gst += lineNet - netExcl;
        } else {
          sub += lineGross;
          disc += lineDisc;
          gst += lineNet * (l.gstRate / 100);
        }
      }
      setState(() {
        _subtotal = sub;
        _discountTotal = disc;
        // Calculate GST based on intra-state vs inter-state
      // Intra-state: origin == POS → CGST + SGST
      // Inter-state: origin != POS → IGST
      final settingsProvider = context.read<SettingsProvider>();
      final originStateCode = settingsProvider.settings['origin_state_code'] ?? '';
      final isIntraState = _posStateCode == originStateCode && originStateCode.isNotEmpty;
      
      if (isIntraState) {
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
            if (_isGstInclusive) {
              final double rateExcl = l.rate / (1 + l.gstRate / 100);
              final double grossExcl = l.quantity * rateExcl;
              final double discExcl = grossExcl * (l.discount / 100);
              final double netExcl = grossExcl - discExcl;
              sub += grossExcl;
              disc += discExcl;
              gst += lineNet - netExcl;
            } else {
              sub += lineGross;
              disc += lineDisc;
              gst += lineNet * (l.gstRate / 100);
            }
          }
          setState(() {
            _subtotal = sub;
            _discountTotal = disc;
            // Calculate GST based on intra-state vs inter-state
              // Intra-state: origin == POS → CGST + SGST
              // Inter-state: origin != POS → IGST
              final settingsProvider = context.read<SettingsProvider>();
              final originStateCode = settingsProvider.settings['origin_state_code'] ?? '';
              final isIntraState = _posStateCode == originStateCode && originStateCode.isNotEmpty;
              
              if (isIntraState) {
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
              'rate': _isGstInclusive ? (l.rate / (1 + l.gstRate / 100)) : l.rate,
              'discount': (l.quantity * (_isGstInclusive ? (l.rate / (1 + l.gstRate / 100)) : l.rate) * l.discount / 100)
                  .toStringAsFixed(4),
              if (RegExp(r'^[0-9]{4,8}$').hasMatch(l.hsnSac))
                'hsn_sac': l.hsnSac,
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
    payload['is_gst_inclusive'] = _isGstInclusive;
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
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
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
    _markDirty();
  }

  void _setLineProduct(int index, ProductModel p) {
    setState(() {
      _lines[index].setProduct(p, widget.config.isPurchase);
    });
    _markDirty();
    _triggerPreview();
  }

  void _removeLine(int index) {
    setState(() {
      _lines[index].dispose();
      _lines.removeAt(index);
    });
    _markDirty();
    _triggerPreview();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
      return;
    }
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
        _markClean();
        _clearDraft();
        HapticHelper.success();
        final docType = _resolvedDocumentType;
        if (docType == 'INVOICE') {
          final invoiceProvider = context.read<InvoiceProvider>();
          final docNum = _invoiceNoCtrl.text;
          // Find the invoice by number in the refreshed list (most reliable after fetchInvoices)
          final matchedInvoice = docNum.isNotEmpty
              ? invoiceProvider.invoices.where((i) => i.invoiceNumber == docNum).firstOrNull
              : null;
          final docId = matchedInvoice?.id;
          final displayNum = docNum.isNotEmpty ? docNum : (matchedInvoice?.invoiceNumber ?? 'Invoice');

          // Pop first, then show snackbar on the parent route
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 8),
              backgroundColor: AppColors.success,
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$displayNum saved',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  if (docId != null) ...[
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => InvoiceDetailView(invoiceId: docId)),
                        );
                      },
                      child: const Text('VIEW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        PrintShareHelper.showShareSheet(
                          context,
                          docLabel: 'Invoice',
                          docNumber: displayNum,
                          docType: 'invoices',
                          docId: docId,
                        );
                      },
                      child: const Text('PRINT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ]
                ],
              ),
            ),
          );
        } else {
          Navigator.pop(context, true);
          _showSnack(widget.config.successMessage);
        }
      } else {
        HapticHelper.error();
      }
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (error) HapticHelper.error();
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

      // ── Step 1: Submit for async OCR ──────────────────────────────
      final previewUri = Uri.parse('${ApiClient.baseUrl}/bills/scan-preview');
      final previewRequest = http.MultipartRequest('POST', previewUri);
      if (ApiClient.accessToken != null) {
        previewRequest.headers['Authorization'] = 'Bearer ${ApiClient.accessToken}';
      }
      if (ApiClient.tenantId != null) {
        previewRequest.headers['X-Tenant-ID'] = ApiClient.tenantId!;
      }
      previewRequest.files.add(http.MultipartFile.fromBytes('file', bytes, filename: picked.name));
      previewRequest.fields['confidence'] = '0.25';

      final previewStreamed = await previewRequest.send();
      final previewResponse = await http.Response.fromStream(previewStreamed);

      if (!mounted) return;

      Map<String, dynamic> previewData = {};

      // 202 = async job submitted, 200 = synchronous fallback
      if (previewResponse.statusCode == 202) {
        // Async path: poll for results
        final submitBody = jsonDecode(previewResponse.body);
        final jobId = submitBody['job_id']?.toString();
        if (jobId == null) {
          _showSnack('Scan job failed to start.', error: true);
          setState(() => _isScanning = false);
          return;
        }

        // Poll every 2 seconds, max 60 seconds
        for (var i = 0; i < 30; i++) {
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;

          final statusUri = Uri.parse('${ApiClient.baseUrl}/bills/scan-status/$jobId');
          final statusResp = await http.get(statusUri, headers: {
            if (ApiClient.accessToken != null)
              'Authorization': 'Bearer ${ApiClient.accessToken}',
            if (ApiClient.tenantId != null)
              'X-Tenant-ID': ApiClient.tenantId!,
          });

          if (statusResp.statusCode == 200) {
            previewData = jsonDecode(statusResp.body) as Map<String, dynamic>;
            break;
          } else if (statusResp.statusCode == 500) {
            final errBody = jsonDecode(statusResp.body);
            _showSnack(errBody['detail']?.toString() ?? 'Scan failed', error: true);
            setState(() => _isScanning = false);
            return;
          }
          // 202 = still processing, continue polling
        }

        if (previewData.isEmpty) {
          _showSnack('Scan timed out after 60 seconds.', error: true);
          setState(() => _isScanning = false);
          return;
        }
      } else if (previewResponse.statusCode == 200) {
        // Synchronous fallback (Celery down)
        final previewBody = jsonDecode(previewResponse.body);
        previewData = previewBody is Map<String, dynamic>
            ? previewBody
            : <String, dynamic>{};
      } else {
        String msg = 'Scan failed (${previewResponse.statusCode})';
        try {
          final b = jsonDecode(previewResponse.body);
          if (b is Map) msg = b['detail']?.toString() ?? msg;
        } catch (_) {}
        _showSnack(msg, error: true);
        setState(() => _isScanning = false);
        return;
      }

      // ── Step 2: Show editable preview dialog ────────────────────────
      final created = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ScannedBillPreviewDialog(
          previewData: previewData,
          onSave: (editedPayload) async {
            // Capture providers before async gap
            final contactProvider = context.read<ContactProvider>();
            final productProvider = context.read<ProductProvider>();
            // Step 3: Call scan-save
            final saveUri = Uri.parse('${ApiClient.baseUrl}/bills/scan-save');
            final saveResponse = await http.post(
              saveUri,
              headers: {
                'Content-Type': 'application/json',
                if (ApiClient.accessToken != null)
                  'Authorization': 'Bearer ${ApiClient.accessToken}',
                if (ApiClient.tenantId != null)
                  'X-Tenant-ID': ApiClient.tenantId!,
              },
              body: jsonEncode(editedPayload),
            );

            if (saveResponse.statusCode == 201) {
              final body = jsonDecode(saveResponse.body);
              final billNumber = body['bill_number']?.toString();
              if (mounted) {
                _showSnack('Bill $billNumber created successfully');
              }
              // Refresh contacts / products in case new ones were created
              await contactProvider.fetchContacts();
              await productProvider.fetchProducts();
              return true;
            } else {
              String msg = 'Failed to save bill (${saveResponse.statusCode})';
              try {
                final b = jsonDecode(saveResponse.body);
                if (b is Map) msg = b['detail']?.toString() ?? msg;
              } catch (_) {}
              if (mounted) _showSnack(msg, error: true);
              return false;
            }
          },
        ),
      );

      if (created == true && mounted) {
        // Pop the form back so the list refreshes
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _showSnack('Scan error: $e', error: true);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = AdaptiveLayout.isDesktop(context);
    final isEdit = widget.editEntity != null;
    final displayTitle = isEdit
        ? 'Edit ${widget.config.title}'
        : widget.config.title;

    String documentStatus = 'DRAFT';
    if (widget.editEntity != null) {
      if (widget.editEntity is InvoiceModel) {
        documentStatus = widget.editEntity.status;
      } else if (widget.editEntity is BillModel) {
        documentStatus = widget.editEntity.status;
      } else if (widget.editEntity is Map) {
        documentStatus = widget.editEntity['status'] ?? 'SAVED';
      }
    }

    // Determine layout columns based on screen width
    final bodyContent = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasRecoveredDraft)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppDraftIndicator(onRecover: _recoverDraft),
            ),
          
          if (isDesktop)
            // Desktop Split Layout
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Inputs & Form Content
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPartiesRow(isDesktop),
                      const SizedBox(height: 12),
                      _buildDocInfoCard(isDesktop),
                      const SizedBox(height: 12),
                      _buildLineItemsSection(isDesktop),
                      const SizedBox(height: 12),
                      _buildAttachmentsAndNotesCard(),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Right Column: Summary Panels
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_gstEnabled) _buildTaxBreakdownCard(),
                      const SizedBox(height: 12),
                      _buildTotalSummaryCard(),
                    ],
                  ),
                ),
              ],
            )
          else
            // Mobile Stacked Layout
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPartiesRow(isDesktop),
                const SizedBox(height: 12),
                _buildDocInfoCard(isDesktop),
                const SizedBox(height: 12),
                _buildLineItemsSection(isDesktop),
                const SizedBox(height: 12),
                if (_gstEnabled) _buildTaxBreakdownCard(),
                const SizedBox(height: 12),
                _buildTotalSummaryCard(),
                const SizedBox(height: 12),
                _buildAttachmentsAndNotesCard(),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    );

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppVoucherHeader(
        title: displayTitle,
        status: documentStatus,
        isDraft: _hasRecoveredDraft,
        onBackPressed: () async {
          if (_isDirty) {
            final shouldPop = await _onWillPop();
            if (shouldPop) Navigator.of(context).pop();
          } else {
            Navigator.of(context).pop();
          }
        },
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
        ],
      ),
      bottomNavigationBar: AppBottomTotalBar(
        subtotal: _subtotal,
        tax: _cgst + _sgst + _igst + _utgst + _cess,
        total: _total,
        onSaveDraft: () async {
          await _saveDraftToDisk();
          _showSnack('Draft saved to local storage');
        },
        onSave: _save,
        isSaving: _isSaving,
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: bodyContent,
      ),
      ),
    );
  }

  Widget _buildDocInfoCard(bool isDesktop) {
    final headerRow = Row(
      children: [
        const Icon(Icons.description_outlined, size: 14, color: AppColors.brandNavy),
        const SizedBox(width: 6),
        Text('DOCUMENT DETAILS', style: AppTextStyles.labelSmall.copyWith(color: AppColors.brandNavy)),
        const Spacer(),
        if (_gstEnabled)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _isGstInclusive,
                activeColor: AppColors.brandNavy,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _isGstInclusive = val;
                    });
                    _triggerPreview();
                  }
                },
              ),
              const Text('GST Inclusive', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
      ],
    );

    final fields = <Widget>[
      Expanded(
        child: AppTextField(
          controller: _invoiceNoCtrl,
          label: widget.config.numberLabel ?? 'Document Number',
          prefixIcon: Icons.tag,
          hintText: _nextNumberPlaceholder ?? 'Auto-generated',
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: AppDateField(
          controller: _issueDateCtrl,
          label: widget.config.isPurchase ? 'Bill Date *' : 'Invoice Date *',
          onTap: () => _pickDate(_issueDateCtrl),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: AppDateField(
          controller: _dueDateCtrl,
          label: 'Due Date',
          onTap: () => _pickDate(_dueDateCtrl),
        ),
      ),
      if (_gstEnabled) ...[
        const SizedBox(width: 12),
        Expanded(
          child: AppDropdown<String>(
            value: _posStateCode,
            label: 'Place of Supply *',
            prefixIcon: Icons.map_outlined,
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
      const SizedBox(width: 12),
      Expanded(
        child: AppTextField(
          controller: _poNumberCtrl,
          label: 'PO / Reference #',
          prefixIcon: Icons.receipt_long_outlined,
        ),
      ),
    ];

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          headerRow,
          const SizedBox(height: 10),
          if (isDesktop)
            Row(children: fields)
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: fields.where((w) => w is! SizedBox).map((w) {
                if (w is Expanded) return w.child;
                return w;
              }).toList().expand((w) => [w, const SizedBox(height: 8)]).toList()..removeLast(),
            ),
        ],
      ),
    );
  }

  Widget _buildPartiesRow(bool isDesktop) {
    final billingStateName = _selectedContact != null && _gstStateNames.containsKey(_selectedContact!.stateCode)
        ? _gstStateNames[_selectedContact!.stateCode]
        : _selectedContact?.stateCode;

    final billToWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPartySelector(
          label: widget.config.contactLabel,
          partyName: _selectedContact?.name,
          gstin: _selectedContact?.gstin,
          state: billingStateName,
          onTap: _openContactSearch,
        ),
        if (widget.config.hasShippingAddress) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Checkbox(
                value: _shipToSameAsBilling,
                activeColor: AppColors.brandNavy,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _shipToSameAsBilling = val;
                      if (_shipToSameAsBilling && _selectedContact != null) {
                        final addr = _selectedContact!.shippingAddress ?? _selectedContact!.billingAddress;
                        _shippingAddrCtrl.text = _flattenAddress(addr);
                      } else if (!_shipToSameAsBilling) {
                        _shippingAddrCtrl.clear();
                      }
                    });
                  }
                },
              ),
              const Text(
                'Shipping same as billing',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ],
    );

    final shipToWidget = widget.config.hasShippingAddress && !_shipToSameAsBilling
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_shipping_outlined, color: AppColors.brandNavy, size: 14),
                      const SizedBox(width: 6),
                      Text('SHIPPING DETAILS', style: AppTextStyles.labelSmall.copyWith(color: AppColors.brandNavy)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _shippingAddrCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Shipping Address *',
                      hintText: 'Enter full shipping address',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    validator: (v) {
                      if (!_shipToSameAsBilling && (v == null || v.trim().isEmpty)) {
                        return 'Shipping address is required';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          )
        : const SizedBox.shrink();

    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: billToWidget),
              if (widget.config.hasShippingAddress && !_shipToSameAsBilling) ...[
                const SizedBox(width: 16),
                Expanded(child: shipToWidget),
              ],
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        billToWidget,
        shipToWidget,
      ],
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
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Navy header row - horizontally scrollable
          Container(
            color: AppColors.brandNavyLight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _gstEnabled ? 992 : 708,
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text('S.No', style: AppTextStyles.button.copyWith(color: Colors.white, fontSize: 11)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 200,
                      child: Text('Item Description *', style: AppTextStyles.button.copyWith(color: Colors.white, fontSize: 11)),
                    ),
                    if (_gstEnabled) ...[
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: 90,
                        child: Text('HSN/SAC *', style: AppTextStyles.button.copyWith(color: Colors.white, fontSize: 11)),
                      ),
                    ],
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 60,
                      child: Text('Qty *', style: AppTextStyles.button.copyWith(color: Colors.white, fontSize: 11), textAlign: TextAlign.center),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 60,
                      child: Text('Unit', style: AppTextStyles.button.copyWith(color: Colors.white, fontSize: 11)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 90,
                      child: Text('Rate (₹) *', style: AppTextStyles.button.copyWith(color: Colors.white, fontSize: 11), textAlign: TextAlign.right),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 70,
                      child: Text('Disc %', style: AppTextStyles.button.copyWith(color: Colors.white, fontSize: 11), textAlign: TextAlign.center),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 100,
                      child: Text('Taxable (₹)', style: AppTextStyles.button.copyWith(color: Colors.white, fontSize: 11), textAlign: TextAlign.right),
                    ),
                    if (_gstEnabled) ...[
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: 70,
                        child: Text('GST %', style: AppTextStyles.button.copyWith(color: Colors.white, fontSize: 11), textAlign: TextAlign.center),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: 100,
                        child: Text('GST Amt (₹)', style: AppTextStyles.button.copyWith(color: Colors.white, fontSize: 11), textAlign: TextAlign.right),
                      ),
                    ],
                    const SizedBox(width: AppSpacing.sm),
                    const SizedBox(width: 36),
                  ],
                ),
              ),
            ),
          ),
          // Scroll hint for horizontal overflow
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 3),
            child: const Row(
              children: [
                Icon(Icons.swipe_right_alt_rounded, size: 11, color: AppColors.textMuted),
                SizedBox(width: 3),
                Text('Scroll right for more columns', style: TextStyle(fontSize: 9, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          if (_lines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No items added yet', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _lines.length,
              itemBuilder: (context, index) {
                final line = _lines[index];
                final double lineGross = line.quantity * line.rate * (1 - line.discount / 100);
                final double taxableValue = _isGstInclusive
                    ? (lineGross / (1 + line.gstRate / 100))
                    : lineGross;
                final double gstAmount = _isGstInclusive
                    ? (lineGross - taxableValue)
                    : (taxableValue * (line.gstRate / 100));
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: _gstEnabled ? 992 : 708,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text('${index + 1}', style: AppTextStyles.bodyMedium),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 200,
                            child: GestureDetector(
                              onTap: () => _openProductSearch(index),
                              child: Container(
                                padding: AppSpacing.inputPaddingCompact,
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.border),
                                  borderRadius: AppRadius.input,
                                ),
                                child: Text(
                                  line.productName.isNotEmpty ? line.productName : 'Select product...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: line.productName.isNotEmpty ? AppColors.textPrimary : AppColors.textMuted,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          if (_gstEnabled) ...[
                            const SizedBox(width: AppSpacing.sm),
                            SizedBox(
                              width: 90,
                              child: AppTextField(
                                controller: line.hsnCtrl,
                                onChanged: (v) { line.hsnSac = v; _markDirty(); },
                                compact: true,
                              ),
                            ),
                          ],
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 60,
                            child: AppTextField(
                              controller: line.qtyCtrl,
                              textAlign: TextAlign.center,
                              compact: true,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Required';
                                final qty = double.tryParse(v);
                                if (qty == null) return 'Enter a valid number';
                                if (qty <= 0) return 'Qty must be > 0';
                                return null;
                              },
                              onChanged: (v) {
                                line.quantity = double.tryParse(v) ?? 1;
                                _markDirty();
                                _triggerPreview();
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 60,
                            child: AppDropdown<String>(
                              value: line.unit,
                              compact: true,
                              items: const [
                                DropdownMenuItem(value: 'Nos', child: Text('Nos')),
                                DropdownMenuItem(value: 'Pcs', child: Text('Pcs')),
                                DropdownMenuItem(value: 'Box', child: Text('Box')),
                              ],
                              onChanged: (v) {
                                if (v != null) { setState(() => line.unit = v); _markDirty(); }
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 90,
                            child: AppTextField(
                              controller: line.rateCtrl,
                              textAlign: TextAlign.right,
                              compact: true,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Required';
                                final rate = double.tryParse(v);
                                if (rate == null) return 'Enter a valid number';
                                if (rate < 0) return 'Rate cannot be negative';
                                return null;
                              },
                              onChanged: (v) {
                                line.rate = double.tryParse(v) ?? 0;
                                _markDirty();
                                _triggerPreview();
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 70,
                            child: AppTextField(
                              controller: line.discCtrl,
                              textAlign: TextAlign.center,
                              compact: true,
                              validator: (v) {
                                if (v != null && v.trim().isNotEmpty) {
                                  final disc = double.tryParse(v);
                                  if (disc == null) return 'Enter a valid number';
                                  if (disc < 0 || disc > 100) return 'Discount must be 0-100%';
                                }
                                return null;
                              },
                              onChanged: (v) {
                                line.discount = double.tryParse(v) ?? 0;
                                _markDirty();
                                _triggerPreview();
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 100,
                            child: Text(
                              '₹${taxableValue.toStringAsFixed(2)}',
                              textAlign: TextAlign.right,
                              style: AppTextStyles.amount,
                            ),
                          ),
                          if (_gstEnabled) ...[
                            const SizedBox(width: AppSpacing.sm),
                            SizedBox(
                              width: 70,
                              child: AppDropdown<String>(
                                value: line.gstRate.toStringAsFixed(0),
                                compact: true,
                                items: const [
                                  DropdownMenuItem(value: '28', child: Text('28%')),
                                  DropdownMenuItem(value: '18', child: Text('18%')),
                                  DropdownMenuItem(value: '12', child: Text('12%')),
                                  DropdownMenuItem(value: '5', child: Text('5%')),
                                  DropdownMenuItem(value: '3', child: Text('3%')),
                                  DropdownMenuItem(value: '0', child: Text('0%')),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => line.gstRate = double.tryParse(v) ?? 18);
                                    _markDirty();
                                    _triggerPreview();
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            SizedBox(
                              width: 100,
                              child: Text(
                                '₹${gstAmount.toStringAsFixed(2)}',
                                textAlign: TextAlign.right,
                                style: AppTextStyles.amount,
                              ),
                            ),
                          ],
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 36,
                            child: IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                              onPressed: () => _removeLine(index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            child: ActionButton(
              label: 'Add Row',
              icon: Icons.add,
              tier: ActionTier.safe,
              onPressed: _addEmptyLine,
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
      onChanged: () { _markDirty(); _triggerPreview(); },
      onRemove: () => _removeLine(index),
      gstEnabled: _gstEnabled,
    );
  }

  Widget _buildAttachmentsAndNotesCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Amount in Words',
                style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                _total > 0
                    ? 'Rupees ${_convertToWords(_total)} Only'
                    : 'Zero Rupees Only',
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandNavy,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _notesCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Notes (Optional)',
              border: InputBorder.none,
              hintText: 'Enter notes...',
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaxBreakdownCard() {
    return AppTaxSummary(
      cgst: _cgst,
      sgst: _sgst,
      igst: _igst,
      utgst: _utgst,
      cess: _cess,
    );
  }

  Widget _buildTotalSummaryCard() {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryRow('Taxable Value', _subtotal),
          if (_discountTotal.abs() > 0.001)
            _SummaryRow('Discount', -_discountTotal, color: AppColors.success),
          _SummaryRow(
            'Tax',
            _cgst + _sgst + _igst + _utgst + _cess,
          ),
          if (_roundOff.abs() > 0.001) _SummaryRow('Round Off', _roundOff),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              Text(
                '₹${_total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.brandNavy,
                ),
              ),
            ],
          ),
          if (_amountPaid > 0) ...[
            const SizedBox(height: 4),
            _SummaryRow('Paid', _amountPaid, color: AppColors.success),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Balance Due',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.error),
                ),
                Text(
                  '₹${(_total - _amountPaid).clamp(0, double.infinity).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTotalsAndBreakdownSection(bool isDesktop) {
    return const SizedBox.shrink();
  }

  String _convertToWords(double val) {
    if (val < 0) return 'Negative ${_convertToWords(-val)}';
    if (val == 0) return 'Zero Rupees Only';
    final whole = val.floor();
    final paise = ((val - whole) * 100 + 0.5).floor();
    final _ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
                   'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
                   'Seventeen', 'Eighteen', 'Nineteen'];
    final _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

    String convertBelowThousand(int n) {
      if (n == 0) return '';
      String r;
      if (n >= 100) {
        r = '${_ones[n ~/ 100]} Hundred ';
        n %= 100;
      } else {
        r = '';
      }
      if (n >= 20) {
        r += '${_tens[n ~/ 10]} ${_ones[n % 10]}'.trim();
      } else if (n > 0) {
        r += _ones[n];
      }
      return r.trim();
    }

    String convert(int n) {
      if (n == 0) return 'Zero';
      final crore = n ~/ 10000000; n %= 10000000;
      final lakh = n ~/ 100000; n %= 100000;
      final thousand = n ~/ 1000; n %= 1000;
      final hundred = n;
      final parts = <String>[];
      if (crore > 0) parts.add('${convertBelowThousand(crore)} Crore');
      if (lakh > 0) parts.add('${convertBelowThousand(lakh)} Lakh');
      if (thousand > 0) parts.add('${convertBelowThousand(thousand)} Thousand');
      if (hundred > 0) parts.add(convertBelowThousand(hundred));
      return parts.join(' ');
    }

    final wholeWords = convert(whole);
    if (paise > 0) {
      return '$wholeWords Rupees and ${convert(paise)} Paise Only';
    }
    return '$wholeWords Rupees Only';
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.caption),
          Text(
            '₹${value.toStringAsFixed(2)}',
            style: AppTextStyles.numeric.copyWith(fontSize: 12, color: color),
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
  final bool gstEnabled;

  const _LineItemCard({
    super.key,
    required this.index,
    required this.line,
    required this.onPickProduct,
    required this.onChanged,
    required this.onRemove,
    this.gstEnabled = true,
  });

  @override
  State<_LineItemCard> createState() => _LineItemCardState();
}

class _LineItemCardState extends State<_LineItemCard> {
  bool _showDetails = false;

  TransactionLineItem get line => widget.line;
  bool get _hasProduct => line.productName.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    _SmallField(
                      label: 'Qty',
                      ctrl: line.qtyCtrl,
                      onChanged: (v) {
                        line.quantity = double.tryParse(v) ?? 1;
                        widget.onChanged();
                      },
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final q = double.tryParse(v);
                        if (q == null) return 'Valid number';
                        if (q <= 0) return 'Must be > 0';
                        return null;
                      },
                    ),
                    const SizedBox(width: 6),
                    _SmallField(
                      label: 'Rate (₹)',
                      ctrl: line.rateCtrl,
                      flex: 2,
                      onChanged: (v) {
                        line.rate = double.tryParse(v) ?? 0;
                        widget.onChanged();
                      },
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final r = double.tryParse(v);
                        if (r == null) return 'Valid number';
                        if (r < 0) return 'Cannot be negative';
                        return null;
                      },
                    ),
                    const SizedBox(width: 6),
                    _SmallField(
                      label: 'Disc %',
                      ctrl: line.discCtrl,
                      onChanged: (v) {
                        line.discount = double.tryParse(v) ?? 0;
                        widget.onChanged();
                      },
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        final d = double.tryParse(v);
                        if (d == null) return 'Valid number';
                        if (d < 0 || d > 100) return 'Must be 0-100%';
                        return null;
                      },
                    ),
                    if (widget.gstEnabled) ...[
                      const SizedBox(width: 6),
                      _SmallField(
                        label: 'GST %',
                        ctrl: line.gstCtrl,
                        onChanged: (v) {
                          line.gstRate = double.tryParse(v) ?? 0;
                          widget.onChanged();
                        },
                        validator: (v) {
                          if (v == null || v.isEmpty) return null;
                          final g = double.tryParse(v);
                          if (g == null || g < 0) return 'Invalid';
                          return null;
                        },
                      ),
                    ],
                  ],
                ),
                if (widget.gstEnabled && _showDetails) ...[
                  const SizedBox(height: 8),
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
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: line.descCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            labelText: 'Item Description',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
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
  final String? Function(String?)? validator;

  const _SmallField({
    required this.label,
    required this.ctrl,
    required this.onChanged,
    this.flex = 1,
    this.validator,
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
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          TextFormField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            onChanged: onChanged,
            validator: validator,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
