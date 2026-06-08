class EstimateModel {
  final String id;
  final String contactId;
  final String estimateNumber;
  final String issueDate;
  final String? dueDate;
  final String status;
  final double subtotal;
  final double discountTotal;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double utgstAmount;
  final double cessAmount;
  final double roundOff;
  final double total;
  final String posStateCode;
  final String? contactName;
  final String createdAt;

  EstimateModel({
    required this.id,
    required this.contactId,
    required this.estimateNumber,
    required this.issueDate,
    this.dueDate,
    required this.status,
    this.subtotal = 0.0,
    this.discountTotal = 0.0,
    this.cgstAmount = 0.0,
    this.sgstAmount = 0.0,
    this.igstAmount = 0.0,
    this.utgstAmount = 0.0,
    this.cessAmount = 0.0,
    this.roundOff = 0.0,
    this.total = 0.0,
    required this.posStateCode,
    this.contactName,
    required this.createdAt,
  });

  factory EstimateModel.fromJson(Map<String, dynamic> json) {
    return EstimateModel(
      id: json['id'] ?? '',
      contactId: json['contact_id'] ?? '',
      estimateNumber: json['estimate_number'] ?? json['invoice_number'] ?? '',
      issueDate: json['issue_date'] ?? '',
      dueDate: json['due_date'],
      status: json['status'] ?? 'DRAFT',
      subtotal: double.tryParse((json['subtotal'] ?? 0.0).toString()) ?? 0.0,
      discountTotal: double.tryParse((json['discount_total'] ?? 0.0).toString()) ?? 0.0,
      cgstAmount: double.tryParse((json['cgst_amount'] ?? 0.0).toString()) ?? 0.0,
      sgstAmount: double.tryParse((json['sgst_amount'] ?? 0.0).toString()) ?? 0.0,
      igstAmount: double.tryParse((json['igst_amount'] ?? 0.0).toString()) ?? 0.0,
      utgstAmount: double.tryParse((json['utgst_amount'] ?? 0.0).toString()) ?? 0.0,
      cessAmount: double.tryParse((json['cess_amount'] ?? 0.0).toString()) ?? 0.0,
      roundOff: double.tryParse((json['round_off'] ?? 0.0).toString()) ?? 0.0,
      total: double.tryParse((json['total'] ?? 0.0).toString()) ?? 0.0,
      posStateCode: json['pos_state_code'] ?? '27',
      contactName: json['contact_name'],
      createdAt: json['created_at'] ?? '',
    );
  }

  bool get isDraft => status == 'DRAFT';
  bool get isIssued => status == 'ISSUED';
  bool get isConverted => status == 'CONVERTED';
  bool get isCancelled => status == 'CANCELLED';
}
