class CashBookRow {
  final String date;
  final String transactionDetails;
  final double? invoiceAmount;
  final double? taxAmount;
  final double amount;

  CashBookRow({
    required this.date,
    required this.transactionDetails,
    this.invoiceAmount,
    this.taxAmount,
    required this.amount,
  });

  factory CashBookRow.fromJson(Map<String, dynamic> json) {
    return CashBookRow(
      date: json['date'] ?? '',
      transactionDetails: json['transaction_details'] ?? '',
      invoiceAmount: json['invoice_amount'] != null ? double.parse(json['invoice_amount'].toString()) : null,
      taxAmount: json['tax_amount'] != null ? double.parse(json['tax_amount'].toString()) : null,
      amount: double.parse((json['amount'] ?? 0).toString()),
    );
  }
}

class CashBookSummary {
  final double cashInflow;
  final double cashOutflow;
  final double closingBalance;
  final double actualCashInHand;
  final double difference;

  CashBookSummary({
    required this.cashInflow,
    required this.cashOutflow,
    required this.closingBalance,
    required this.actualCashInHand,
    required this.difference,
  });

  factory CashBookSummary.fromJson(Map<String, dynamic> json) {
    return CashBookSummary(
      cashInflow: double.parse((json['cash_inflow'] ?? 0).toString()),
      cashOutflow: double.parse((json['cash_outflow'] ?? 0).toString()),
      closingBalance: double.parse((json['closing_balance'] ?? 0).toString()),
      actualCashInHand: double.parse((json['actual_cash_in_hand'] ?? 0).toString()),
      difference: double.parse((json['difference'] ?? 0).toString()),
    );
  }
}

class CashBookTaxSummary {
  final double taxPaid;
  final double taxReceived;
  final double taxPayable;

  CashBookTaxSummary({
    required this.taxPaid,
    required this.taxReceived,
    required this.taxPayable,
  });

  factory CashBookTaxSummary.fromJson(Map<String, dynamic> json) {
    return CashBookTaxSummary(
      taxPaid: double.parse((json['tax_paid'] ?? 0).toString()),
      taxReceived: double.parse((json['tax_received'] ?? 0).toString()),
      taxPayable: double.parse((json['tax_payable'] ?? 0).toString()),
    );
  }
}

class CashBookResponse {
  final String periodStart;
  final String periodEnd;
  final double openingBalance;
  final List<CashBookRow> inflows;
  final List<CashBookRow> outflows;
  final CashBookSummary summary;
  final CashBookTaxSummary taxSummary;

  CashBookResponse({
    required this.periodStart,
    required this.periodEnd,
    required this.openingBalance,
    required this.inflows,
    required this.outflows,
    required this.summary,
    required this.taxSummary,
  });

  factory CashBookResponse.fromJson(Map<String, dynamic> json) {
    return CashBookResponse(
      periodStart: json['period_start'] ?? '',
      periodEnd: json['period_end'] ?? '',
      openingBalance: double.parse((json['opening_balance'] ?? 0).toString()),
      inflows: (json['inflows'] as List?)?.map((i) => CashBookRow.fromJson(i)).toList() ?? [],
      outflows: (json['outflows'] as List?)?.map((i) => CashBookRow.fromJson(i)).toList() ?? [],
      summary: CashBookSummary.fromJson(json['summary'] ?? {}),
      taxSummary: CashBookTaxSummary.fromJson(json['tax_summary'] ?? {}),
    );
  }
}
