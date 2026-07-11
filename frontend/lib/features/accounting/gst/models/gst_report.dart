/// GST report models.
library;

import 'package:flutter/foundation.dart';

/// A single GST liability/input line.
@immutable
class GstLine {
  const GstLine({
    this.invoiceNumber = '',
    this.invoiceDate = '',
    this.contactName = '',
    this.taxableValue = 0,
    this.cgst = 0,
    this.sgst = 0,
    this.igst = 0,
    this.cess = 0,
    this.totalTax = 0,
  });

  final String invoiceNumber;
  final String invoiceDate;
  final String contactName;
  final double taxableValue;
  final double cgst;
  final double sgst;
  final double igst;
  final double cess;
  final double totalTax;

  factory GstLine.fromJson(Map<String, dynamic> json) => GstLine(
    invoiceNumber: json['invoice_number'] as String? ?? '',
    invoiceDate: json['invoice_date'] as String? ?? '',
    contactName: json['contact_name'] as String? ?? '',
    taxableValue: _num(json['taxable_value']),
    cgst: _num(json['cgst']),
    sgst: _num(json['sgst']),
    igst: _num(json['igst']),
    cess: _num(json['cess']),
    totalTax: _num(json['total_tax']),
  );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// GST summary report.
@immutable
class GstReport {
  const GstReport({
    this.outputGstLines = const [],
    this.totalOutputGst = 0,
    this.inputGstLines = const [],
    this.totalInputGst = 0,
    this.netGstLiability = 0,
    this.reverseChargeLines = const [],
    this.totalReverseCharge = 0,
  });

  final List<GstLine> outputGstLines;
  final double totalOutputGst;
  final List<GstLine> inputGstLines;
  final double totalInputGst;
  final double netGstLiability;
  final List<GstLine> reverseChargeLines;
  final double totalReverseCharge;

  factory GstReport.fromJson(Map<String, dynamic> json) => GstReport(
    outputGstLines:
        (json['output_gst_lines'] as List?)
            ?.map((e) => GstLine.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    totalOutputGst: _num(json['total_output_gst']),
    inputGstLines:
        (json['input_gst_lines'] as List?)
            ?.map((e) => GstLine.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    totalInputGst: _num(json['total_input_gst']),
    netGstLiability: _num(json['net_gst_liability']),
    reverseChargeLines:
        (json['reverse_charge_lines'] as List?)
            ?.map((e) => GstLine.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    totalReverseCharge: _num(json['total_reverse_charge']),
  );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
