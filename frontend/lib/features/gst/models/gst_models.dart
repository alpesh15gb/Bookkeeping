/// GST compliance data models — mirrors backend gst_schemas.py and
/// report_schemas.py response types.
library;

import 'package:flutter/foundation.dart';

double _gstDouble(Object? value) => switch (value) {
  num n => n.toDouble(),
  String s => double.tryParse(s) ?? 0,
  _ => 0,
};

@immutable
class Gstr2PurchaseLine {
  const Gstr2PurchaseLine({
    required this.vendorName,
    required this.vendorGstin,
    required this.billNumber,
    required this.billDate,
    required this.taxableValue,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.igstAmount,
    required this.totalValue,
  });

  factory Gstr2PurchaseLine.fromJson(Map<String, dynamic> json) =>
      Gstr2PurchaseLine(
        vendorName: (json['vendor_name'] ?? '').toString(),
        vendorGstin: (json['vendor_gstin'] ?? 'Unregistered').toString(),
        billNumber: (json['bill_number'] ?? '').toString(),
        billDate: (json['bill_date'] ?? '').toString(),
        taxableValue: _gstDouble(json['taxable_value']),
        cgstAmount: _gstDouble(json['cgst_amount']),
        sgstAmount:
            _gstDouble(json['sgst_amount']) + _gstDouble(json['utgst_amount']),
        igstAmount: _gstDouble(json['igst_amount']),
        totalValue: _gstDouble(json['total_value']),
      );

  final String vendorName;
  final String vendorGstin;
  final String billNumber;
  final String billDate;
  final double taxableValue;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double totalValue;
}

@immutable
class Gstr2Summary {
  const Gstr2Summary({required this.registered, required this.unregistered});

  factory Gstr2Summary.fromJson(Map<String, dynamic> json) => Gstr2Summary(
    registered: ((json['b2b_purchases'] as List?) ?? const [])
        .map(
          (e) =>
              Gstr2PurchaseLine.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    unregistered: ((json['b2bur_purchases'] as List?) ?? const [])
        .map(
          (e) =>
              Gstr2PurchaseLine.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
  );

  final List<Gstr2PurchaseLine> registered;
  final List<Gstr2PurchaseLine> unregistered;
  List<Gstr2PurchaseLine> get all => [...registered, ...unregistered];
}

// ---------------------------------------------------------------------------
// GSTR-1 Detail Models (from /gst/gstr1 — gst_schemas)
// ---------------------------------------------------------------------------

/// B2B registered-sale line (detailed).
@immutable
class Gstr1B2BLine {
  const Gstr1B2BLine({
    this.customerName = '',
    this.customerGstin = '',
    this.invoiceNumber = '',
    this.invoiceDate = '',
    this.posStateCode = '',
    this.taxableValue = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.igstAmount = 0,
    this.utgstAmount = 0,
    this.cessAmount = 0,
    this.totalValue = 0,
  });

  final String customerName;
  final String customerGstin;
  final String invoiceNumber;
  final String invoiceDate;
  final String posStateCode;
  final double taxableValue;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double utgstAmount;
  final double cessAmount;
  final double totalValue;

  factory Gstr1B2BLine.fromJson(Map<String, dynamic> json) => Gstr1B2BLine(
    customerName: json['customer_name'] as String? ?? '',
    customerGstin: json['customer_gstin'] as String? ?? '',
    invoiceNumber: json['invoice_number'] as String? ?? '',
    invoiceDate: _dateStr(json['invoice_date']),
    posStateCode: json['pos_state_code'] as String? ?? '',
    taxableValue: _num(json['taxable_value']),
    cgstAmount: _num(json['cgst_amount']),
    sgstAmount: _num(json['sgst_amount']),
    igstAmount: _num(json['igst_amount']),
    utgstAmount: _num(json['utgst_amount']),
    cessAmount: _num(json['cess_amount']),
    totalValue: _num(json['total_value']),
  );
}

/// B2C Large (inter-state > 2.5L).
@immutable
class Gstr1B2CLLine {
  const Gstr1B2CLLine({
    this.invoiceNumber = '',
    this.invoiceDate = '',
    this.posStateCode = '',
    this.taxableValue = 0,
    this.igstAmount = 0,
    this.totalValue = 0,
  });

  final String invoiceNumber;
  final String invoiceDate;
  final String posStateCode;
  final double taxableValue;
  final double igstAmount;
  final double totalValue;

  factory Gstr1B2CLLine.fromJson(Map<String, dynamic> json) => Gstr1B2CLLine(
    invoiceNumber: json['invoice_number'] as String? ?? '',
    invoiceDate: _dateStr(json['invoice_date']),
    posStateCode: json['pos_state_code'] as String? ?? '',
    taxableValue: _num(json['taxable_value']),
    igstAmount: _num(json['igst_amount']),
    totalValue: _num(json['total_value']),
  );
}

/// B2C Small (aggregated by rate + POS code).
@immutable
class Gstr1B2CSLine {
  const Gstr1B2CSLine({
    this.posStateCode = '',
    this.gstRate = 0,
    this.taxableValue = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.igstAmount = 0,
    this.utgstAmount = 0,
    this.cessAmount = 0,
  });

  final String posStateCode;
  final double gstRate;
  final double taxableValue;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double utgstAmount;
  final double cessAmount;

  factory Gstr1B2CSLine.fromJson(Map<String, dynamic> json) => Gstr1B2CSLine(
    posStateCode: json['pos_state_code'] as String? ?? '',
    gstRate: _num(json['gst_rate']),
    taxableValue: _num(json['taxable_value']),
    cgstAmount: _num(json['cgst_amount']),
    sgstAmount: _num(json['sgst_amount']),
    igstAmount: _num(json['igst_amount']),
    utgstAmount: _num(json['utgst_amount']),
    cessAmount: _num(json['cess_amount']),
  );
}

/// Credit / Debit note line.
@immutable
class Gstr1NoteLine {
  const Gstr1NoteLine({
    this.noteNumber = '',
    this.noteDate = '',
    this.noteType = '',
    this.invoiceNumber,
    this.customerGstin,
    this.reason,
    this.taxableValue = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.igstAmount = 0,
    this.utgstAmount = 0,
    this.cessAmount = 0,
    this.totalValue = 0,
  });

  final String noteNumber;
  final String noteDate;
  final String noteType;
  final String? invoiceNumber;
  final String? customerGstin;
  final String? reason;
  final double taxableValue;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double utgstAmount;
  final double cessAmount;
  final double totalValue;

  factory Gstr1NoteLine.fromJson(Map<String, dynamic> json) => Gstr1NoteLine(
    noteNumber: json['note_number'] as String? ?? '',
    noteDate: _dateStr(json['note_date']),
    noteType: json['note_type'] as String? ?? '',
    invoiceNumber: json['invoice_number'] as String?,
    customerGstin: json['customer_gstin'] as String?,
    reason: json['reason'] as String?,
    taxableValue: _num(json['taxable_value']),
    cgstAmount: _num(json['cgst_amount']),
    sgstAmount: _num(json['sgst_amount']),
    igstAmount: _num(json['igst_amount']),
    utgstAmount: _num(json['utgst_amount']),
    cessAmount: _num(json['cess_amount']),
    totalValue: _num(json['total_value']),
  );
}

/// HSN summary line.
@immutable
class Gstr1HSNLine {
  const Gstr1HSNLine({
    this.hsnSac = '',
    this.description = '',
    this.uom = '',
    this.totalQuantity = 0,
    this.totalValue = 0,
    this.taxableValue = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.igstAmount = 0,
    this.utgstAmount = 0,
    this.cessAmount = 0,
  });

  final String hsnSac;
  final String description;
  final String uom;
  final double totalQuantity;
  final double totalValue;
  final double taxableValue;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double utgstAmount;
  final double cessAmount;

  factory Gstr1HSNLine.fromJson(Map<String, dynamic> json) => Gstr1HSNLine(
    hsnSac: json['hsn_sac'] as String? ?? '',
    description: json['description'] as String? ?? '',
    uom: json['uom'] as String? ?? '',
    totalQuantity: _num(json['total_quantity']),
    totalValue: _num(json['total_value']),
    taxableValue: _num(json['taxable_value']),
    cgstAmount: _num(json['cgst_amount']),
    sgstAmount: _num(json['sgst_amount']),
    igstAmount: _num(json['igst_amount']),
    utgstAmount: _num(json['utgst_amount']),
    cessAmount: _num(json['cess_amount']),
  );
}

/// Full GSTR-1 response (gst_schemas style).
@immutable
class Gstr1Summary {
  const Gstr1Summary({
    this.b2b = const [],
    this.b2cl = const [],
    this.b2cs = const [],
    this.cdnr = const [],
    this.cdnur = const [],
    this.hsnSummary = const [],
  });

  final List<Gstr1B2BLine> b2b;
  final List<Gstr1B2CLLine> b2cl;
  final List<Gstr1B2CSLine> b2cs;
  final List<Gstr1NoteLine> cdnr;
  final List<Gstr1NoteLine> cdnur;
  final List<Gstr1HSNLine> hsnSummary;

  /// Aggregated taxable value across all sections.
  double get totalTaxableValue {
    double sum = 0;
    for (final l in b2b) sum += l.taxableValue;
    for (final l in b2cl) sum += l.taxableValue;
    for (final l in b2cs) sum += l.taxableValue;
    for (final l in cdnr) sum += l.taxableValue;
    for (final l in cdnur) sum += l.taxableValue;
    return sum;
  }

  double get totalCgst {
    double sum = 0;
    for (final l in b2b) sum += l.cgstAmount;
    for (final l in b2cs) sum += l.cgstAmount;
    for (final l in cdnr) sum += l.cgstAmount;
    for (final l in cdnur) sum += l.cgstAmount;
    return sum;
  }

  double get totalSgst {
    double sum = 0;
    for (final l in b2b) sum += l.sgstAmount;
    for (final l in b2cs) sum += l.sgstAmount;
    for (final l in cdnr) sum += l.sgstAmount;
    for (final l in cdnur) sum += l.sgstAmount;
    return sum;
  }

  double get totalIgst {
    double sum = 0;
    for (final l in b2b) sum += l.igstAmount;
    for (final l in b2cl) sum += l.igstAmount;
    for (final l in b2cs) sum += l.igstAmount;
    for (final l in cdnr) sum += l.igstAmount;
    for (final l in cdnur) sum += l.igstAmount;
    return sum;
  }

  double get totalOutputGst => totalCgst + totalSgst + totalIgst;

  int get totalInvoices => b2b.length + b2cl.length;

  factory Gstr1Summary.fromJson(Map<String, dynamic> json) => Gstr1Summary(
    b2b: _list(json['b2b'], Gstr1B2BLine.fromJson),
    b2cl: _list(json['b2cl'], Gstr1B2CLLine.fromJson),
    b2cs: _list(json['b2cs'], Gstr1B2CSLine.fromJson),
    cdnr: _list(json['cdnr'], Gstr1NoteLine.fromJson),
    cdnur: _list(json['cdnur'], Gstr1NoteLine.fromJson),
    hsnSummary: _list(json['hsn_summary'], Gstr1HSNLine.fromJson),
  );
}

// ---------------------------------------------------------------------------
// GSTR-3B Models (from /reports/gst/gstr3b — report_schemas)
// ---------------------------------------------------------------------------

/// Outward taxable supply section (Table 3.1).
@immutable
class Gstr3BOutwardSection {
  const Gstr3BOutwardSection({
    this.taxableValue = 0,
    this.integratedTax = 0,
    this.centralTax = 0,
    this.stateUtTax = 0,
    this.cess = 0,
  });

  final double taxableValue;
  final double integratedTax;
  final double centralTax;
  final double stateUtTax;
  final double cess;

  factory Gstr3BOutwardSection.fromJson(Map<String, dynamic> json) =>
      Gstr3BOutwardSection(
        taxableValue: _num(json['taxable_value']),
        integratedTax: _num(json['integrated_tax']),
        centralTax: _num(json['central_tax']),
        stateUtTax: _num(json['state_ut_tax']),
        cess: _num(json['cess']),
      );
}

/// Inward ITC section (Table 4).
@immutable
class Gstr3BInwardSection {
  const Gstr3BInwardSection({
    this.integratedTax = 0,
    this.centralTax = 0,
    this.stateUtTax = 0,
    this.cess = 0,
  });

  final double integratedTax;
  final double centralTax;
  final double stateUtTax;
  final double cess;

  factory Gstr3BInwardSection.fromJson(Map<String, dynamic> json) =>
      Gstr3BInwardSection(
        integratedTax: _num(json['integrated_tax']),
        centralTax: _num(json['central_tax']),
        stateUtTax: _num(json['state_ut_tax']),
        cess: _num(json['cess']),
      );
}

/// Full GSTR-3B return summary.
@immutable
class Gstr3BSummary {
  const Gstr3BSummary({
    this.periodStart = '',
    this.periodEnd = '',
    this.gstin,
    this.outwardTaxableSupplies = const Gstr3BOutwardSection(),
    this.nilRatedSupplies = const Gstr3BOutwardSection(),
    this.inwardSuppliesItc = const Gstr3BInwardSection(),
    this.netTaxPayableIgst = 0,
    this.netTaxPayableCgst = 0,
    this.netTaxPayableSgst = 0,
    this.netTaxPayableCess = 0,
  });

  final String periodStart;
  final String periodEnd;
  final String? gstin;
  final Gstr3BOutwardSection outwardTaxableSupplies;
  final Gstr3BOutwardSection nilRatedSupplies;
  final Gstr3BInwardSection inwardSuppliesItc;
  final double netTaxPayableIgst;
  final double netTaxPayableCgst;
  final double netTaxPayableSgst;
  final double netTaxPayableCess;

  double get totalOutputTax =>
      outwardTaxableSupplies.integratedTax +
      outwardTaxableSupplies.centralTax +
      outwardTaxableSupplies.stateUtTax +
      outwardTaxableSupplies.cess;

  double get totalItc =>
      inwardSuppliesItc.integratedTax +
      inwardSuppliesItc.centralTax +
      inwardSuppliesItc.stateUtTax +
      inwardSuppliesItc.cess;

  double get netTaxPayable =>
      netTaxPayableIgst +
      netTaxPayableCgst +
      netTaxPayableSgst +
      netTaxPayableCess;

  factory Gstr3BSummary.fromJson(Map<String, dynamic> json) => Gstr3BSummary(
    periodStart: json['period_start']?.toString() ?? '',
    periodEnd: json['period_end']?.toString() ?? '',
    gstin: json['gstin'] as String?,
    outwardTaxableSupplies: Gstr3BOutwardSection.fromJson(
      (json['outward_taxable_supplies'] as Map<String, dynamic>?) ?? {},
    ),
    nilRatedSupplies: Gstr3BOutwardSection.fromJson(
      (json['nil_rated_supplies'] as Map<String, dynamic>?) ?? {},
    ),
    inwardSuppliesItc: Gstr3BInwardSection.fromJson(
      (json['inward_supplies_itc'] as Map<String, dynamic>?) ?? {},
    ),
    netTaxPayableIgst: _num(json['net_tax_payable_igst']),
    netTaxPayableCgst: _num(json['net_tax_payable_cgst']),
    netTaxPayableSgst: _num(json['net_tax_payable_sgst']),
    netTaxPayableCess: _num(json['net_tax_payable_cess']),
  );
}

// ---------------------------------------------------------------------------
// GST Return CRUD Models (from /gst/returns)
// ---------------------------------------------------------------------------

/// GST return tracking record.
@immutable
class GstReturn {
  const GstReturn({
    this.id = '',
    this.returnType = '',
    this.periodStart = '',
    this.periodEnd = '',
    this.status = 'DRAFT',
    this.filedAt,
    this.arn,
    this.createdAt = '',
    this.updatedAt = '',
  });

  final String id;
  final String returnType;
  final String periodStart;
  final String periodEnd;
  final String status;
  final String? filedAt;
  final String? arn;
  final String createdAt;
  final String updatedAt;

  String get periodLabel {
    try {
      final parts = periodStart.split('-');
      if (parts.length >= 2) {
        final month = int.parse(parts[1]);
        final year = int.parse(parts[0]);
        const months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        return '${months[month - 1]} $year';
      }
    } catch (e) {
      debugPrint('GstReturn.label: failed to format period — $e');
    }
    return periodStart;
  }

  factory GstReturn.fromJson(Map<String, dynamic> json) => GstReturn(
    id: (json['id'] ?? '').toString(),
    returnType: json['return_type'] as String? ?? '',
    periodStart: json['period_start']?.toString() ?? '',
    periodEnd: json['period_end']?.toString() ?? '',
    status: json['status'] as String? ?? 'DRAFT',
    filedAt: json['filed_at']?.toString(),
    arn: json['arn'] as String?,
    createdAt: json['created_at']?.toString() ?? '',
    updatedAt: json['updated_at']?.toString() ?? '',
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

double _num(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

String _dateStr(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  return v.toString();
}

List<T> _list<T>(dynamic jsonList, T Function(Map<String, dynamic>) fromJson) {
  if (jsonList is! List) return [];
  return jsonList.whereType<Map<String, dynamic>>().map(fromJson).toList();
}
