class ExpenseModel {
  final String id;
  final String tenantId;
  final String expenseNumber;
  final String expenseCategoryId;
  final String? bankAccountId;
  final String expenseDate;
  final String? vendorName;
  final String? description;
  final double amount;
  final double gstRate;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double utgstAmount;
  final double cessAmount;
  final double roundOff;
  final double total;
  final String status;
  final String? categoryName;
  final String createdAt;
  final String? updatedAt;

  ExpenseModel({
    required this.id,
    required this.tenantId,
    required this.expenseNumber,
    required this.expenseCategoryId,
    this.bankAccountId,
    required this.expenseDate,
    this.vendorName,
    this.description,
    required this.amount,
    this.gstRate = 0.0,
    this.cgstAmount = 0.0,
    this.sgstAmount = 0.0,
    this.igstAmount = 0.0,
    this.utgstAmount = 0.0,
    this.cessAmount = 0.0,
    this.roundOff = 0.0,
    required this.total,
    required this.status,
    this.categoryName,
    required this.createdAt,
    this.updatedAt,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      id: json['id'] ?? '',
      tenantId: json['tenant_id'] ?? '',
      expenseNumber: json['expense_number'] ?? '',
      expenseCategoryId: json['expense_category_id'] ?? '',
      bankAccountId: json['bank_account_id'],
      expenseDate: json['expense_date'] ?? '',
      vendorName: json['vendor_name'],
      description: json['description'],
      amount: double.parse((json['amount'] ?? 0.0).toString()),
      gstRate: double.parse((json['gst_rate'] ?? 0.0).toString()),
      cgstAmount: double.parse((json['cgst_amount'] ?? 0.0).toString()),
      sgstAmount: double.parse((json['sgst_amount'] ?? 0.0).toString()),
      igstAmount: double.parse((json['igst_amount'] ?? 0.0).toString()),
      utgstAmount: double.parse((json['utgst_amount'] ?? 0.0).toString()),
      cessAmount: double.parse((json['cess_amount'] ?? 0.0).toString()),
      roundOff: double.parse((json['round_off'] ?? 0.0).toString()),
      total: double.parse((json['total'] ?? 0.0).toString()),
      status: json['status'] ?? 'DRAFT',
      categoryName: json['category_name'],
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tenant_id': tenantId,
    'expense_number': expenseNumber,
    'expense_category_id': expenseCategoryId,
    'bank_account_id': bankAccountId,
    'expense_date': expenseDate,
    'vendor_name': vendorName,
    'description': description,
    'amount': amount,
    'gst_rate': gstRate,
    'cgst_amount': cgstAmount,
    'sgst_amount': sgstAmount,
    'igst_amount': igstAmount,
    'utgst_amount': utgstAmount,
    'cess_amount': cessAmount,
    'round_off': roundOff,
    'total': total,
    'status': status,
    'category_name': categoryName,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  bool get isDraft => status == 'DRAFT';
  bool get isPosted => status == 'POSTED';
  bool get isCancelled => status == 'CANCELLED';
}
