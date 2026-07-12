/// Report data models — Sales Register, Purchase Register, Party Statement,
/// and a lightweight ContactSummary for autocomplete pickers.
library;

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Sales Register — mirrors GET /sales/transactions response item
// ---------------------------------------------------------------------------

@immutable
class SalesTransaction {
  const SalesTransaction({
    this.id = '',
    this.invoiceNumber = '',
    this.issueDate = '',
    this.customerName = '',
    this.subtotal = 0,
    this.taxTotal = 0,
    this.total = 0,
    this.amountPaid = 0,
    this.status = '',
  });

  final String id;
  final String invoiceNumber;
  final String issueDate;
  final String customerName;
  final double subtotal;
  final double taxTotal;
  final double total;
  final double amountPaid;
  final String status;

  factory SalesTransaction.fromJson(Map<String, dynamic> json) =>
      SalesTransaction(
        id: (json['id'] ?? '').toString(),
        invoiceNumber: json['invoice_number'] as String? ?? '',
        issueDate: json['issue_date'] as String? ?? '',
        customerName: json['customer_name'] as String? ?? '',
        subtotal: _num(json['subtotal']),
        taxTotal: _num(json['tax_total']),
        total: _num(json['total']),
        amountPaid: _num(json['amount_paid']),
        status: json['status'] as String? ?? '',
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

// ---------------------------------------------------------------------------
// Purchase Register — mirrors GET /bills response item (BillListResponse)
// ---------------------------------------------------------------------------

@immutable
class PurchaseTransaction {
  const PurchaseTransaction({
    this.id = '',
    this.billNumber = '',
    this.issueDate = '',
    this.vendorName = '',
    this.total = 0,
    this.amountPaid = 0,
    this.status = '',
  });

  final String id;
  final String billNumber;
  final String issueDate;
  final String vendorName;
  final double total;
  final double amountPaid;
  final String status;

  factory PurchaseTransaction.fromJson(Map<String, dynamic> json) =>
      PurchaseTransaction(
        id: (json['id'] ?? '').toString(),
        billNumber: json['bill_number'] as String? ?? '',
        issueDate: json['issue_date'] as String? ?? '',
        vendorName: json['contact_name'] as String? ?? '',
        total: _num(json['total']),
        amountPaid: _num(json['amount_paid']),
        status: json['status'] as String? ?? '',
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

// ---------------------------------------------------------------------------
// Party Statement (Customer / Vendor Ledger) — mirrors PartyStatementResponse
// ---------------------------------------------------------------------------

@immutable
class PartyStatementRow {
  const PartyStatementRow({
    this.date = '',
    this.particulars = '',
    this.voucherType = '',
    this.voucherNo = '',
    this.debit,
    this.credit,
    this.balance = '',
  });

  final String date;
  final String particulars;
  final String voucherType;
  final String voucherNo;
  final double? debit;
  final double? credit;
  final String balance;

  factory PartyStatementRow.fromJson(Map<String, dynamic> json) =>
      PartyStatementRow(
        date: json['date'] as String? ?? '',
        particulars: json['particulars'] as String? ?? '',
        voucherType: json['voucher_type'] as String? ?? '',
        voucherNo: json['voucher_no'] as String? ?? '',
        debit: json['debit'] != null ? _num(json['debit']) : null,
        credit: json['credit'] != null ? _num(json['credit']) : null,
        balance: json['balance'] as String? ?? '',
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

@immutable
class PartyStatementSummary {
  const PartyStatementSummary({
    this.openingBalance = 0,
    this.totalSales = 0,
    this.totalReceipts = 0,
    this.totalPurchases = 0,
    this.totalPayments = 0,
    this.closingOutstanding = 0,
  });

  final double openingBalance;
  final double totalSales;
  final double totalReceipts;
  final double totalPurchases;
  final double totalPayments;
  final double closingOutstanding;

  factory PartyStatementSummary.fromJson(Map<String, dynamic> json) =>
      PartyStatementSummary(
        openingBalance: _num(json['opening_balance']),
        totalSales: _num(json['total_sales']),
        totalReceipts: _num(json['total_receipts']),
        totalPurchases: _num(json['total_purchases']),
        totalPayments: _num(json['total_payments']),
        closingOutstanding: _num(json['closing_outstanding']),
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

@immutable
class PartyStatement {
  const PartyStatement({
    this.contactId = '',
    this.contactName = '',
    this.contactType = '',
    this.address,
    this.gstin,
    this.phone,
    this.startDate = '',
    this.endDate = '',
    this.ledger = const [],
    this.summary = const PartyStatementSummary(),
  });

  final String contactId;
  final String contactName;
  final String contactType;
  final String? address;
  final String? gstin;
  final String? phone;
  final String startDate;
  final String endDate;
  final List<PartyStatementRow> ledger;
  final PartyStatementSummary summary;

  factory PartyStatement.fromJson(Map<String, dynamic> json) =>
      PartyStatement(
        contactId: (json['contact_id'] ?? '').toString(),
        contactName: json['contact_name'] as String? ?? '',
        contactType: json['contact_type'] as String? ?? '',
        address: json['address'] as String?,
        gstin: json['gstin'] as String?,
        phone: json['phone'] as String?,
        startDate: json['start_date'] as String? ?? '',
        endDate: json['end_date'] as String? ?? '',
        ledger: (json['ledger'] as List?)
                ?.map(
                  (e) => PartyStatementRow.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            [],
        summary: json['summary'] is Map<String, dynamic>
            ? PartyStatementSummary.fromJson(
                json['summary'] as Map<String, dynamic>,
              )
            : const PartyStatementSummary(),
      );
}

// ---------------------------------------------------------------------------
// Contact Summary — lightweight model for autocomplete pickers
// ---------------------------------------------------------------------------

@immutable
class ContactSummary {
  const ContactSummary({
    this.id = '',
    this.name = '',
    this.contactType = '',
  });

  final String id;
  final String name;
  final String contactType;

  factory ContactSummary.fromJson(Map<String, dynamic> json) =>
      ContactSummary(
        id: (json['id'] ?? '').toString(),
        name: json['name'] as String? ?? '',
        contactType: json['contact_type'] as String? ?? '',
      );
}
