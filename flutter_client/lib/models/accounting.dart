class AccountModel {
  final String id;
  final String tenantId;
  final String name;
  final String code;
  final String accountType;
  final String? parentId;
  final double openingBalance;
  final double currentBalance;
  final bool isActive;
  final String createdAt;
  final String? updatedAt;

  AccountModel({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.code,
    required this.accountType,
    this.parentId,
    this.openingBalance = 0.0,
    this.currentBalance = 0.0,
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
  });

  factory AccountModel.fromJson(Map<String, dynamic> json) {
    return AccountModel(
      id: json['id'] ?? '',
      tenantId: json['tenant_id'] ?? '',
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      accountType: json['account_type'] ?? 'ASSET',
      parentId: json['parent_id'],
      openingBalance: double.parse((json['opening_balance'] ?? 0.0).toString()),
      currentBalance: double.parse((json['current_balance'] ?? 0.0).toString()),
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'],
    );
  }

  bool get isAsset => accountType == 'ASSET';
  bool get isLiability => accountType == 'LIABILITY';
  bool get isEquity => accountType == 'EQUITY';
  bool get isRevenue => accountType == 'REVENUE';
  bool get isExpense => accountType == 'EXPENSE';
}

class JournalEntryModel {
  final String id;
  final String tenantId;
  final String entryDate;
  final String referenceNumber;
  final String? description;
  final String? sourceType;
  final String? sourceId;
  final bool isLocked;
  final String createdAt;
  final List<JournalLineModel> lines;

  JournalEntryModel({
    required this.id,
    required this.tenantId,
    required this.entryDate,
    required this.referenceNumber,
    this.description,
    this.sourceType,
    this.sourceId,
    this.isLocked = false,
    required this.createdAt,
    this.lines = const [],
  });

  factory JournalEntryModel.fromJson(Map<String, dynamic> json) {
    return JournalEntryModel(
      id: json['id'] ?? '',
      tenantId: json['tenant_id'] ?? '',
      entryDate: json['entry_date'] ?? '',
      referenceNumber: json['reference_number'] ?? '',
      description: json['description'],
      sourceType: json['source_type'],
      sourceId: json['source_id'],
      isLocked: json['is_locked'] ?? false,
      createdAt: json['created_at'] ?? '',
      lines: (json['lines'] as List<dynamic>?)
          ?.map((l) => JournalLineModel.fromJson(l))
          .toList() ?? [],
    );
  }

  double get totalDebits => lines
      .where((l) => l.direction == 'DEBIT')
      .fold(0.0, (sum, l) => sum + l.amount);

  double get totalCredits => lines
      .where((l) => l.direction == 'CREDIT')
      .fold(0.0, (sum, l) => sum + l.amount);

  bool get isBalanced => (totalDebits - totalCredits).abs() < 0.01;
}

class JournalLineModel {
  final String id;
  final String accountId;
  final String? accountName;
  final double amount;
  final String direction;
  final String? narration;

  JournalLineModel({
    required this.id,
    required this.accountId,
    this.accountName,
    required this.amount,
    required this.direction,
    this.narration,
  });

  factory JournalLineModel.fromJson(Map<String, dynamic> json) {
    return JournalLineModel(
      id: json['id'] ?? '',
      accountId: json['account_id'] ?? '',
      accountName: json['account_name'],
      amount: double.parse((json['amount'] ?? 0.0).toString()),
      direction: json['direction'] ?? 'DEBIT',
      narration: json['narration'],
    );
  }

  bool get isDebit => direction == 'DEBIT';
  bool get isCredit => direction == 'CREDIT';
}
