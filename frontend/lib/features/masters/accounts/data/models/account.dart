/// Account model — matches AccountResponse / AccountCreate / AccountUpdate
/// from the backend (src/schemas/master_schemas.py).
///
/// Future-proofing fields the backend does not yet expose (gst_applicable,
/// cost_center, department, branch, currency, reconciliation, cash_flow_category)
/// are NOT added here per the architecture rule "match the backend DTOs
/// exactly". They will be added when the backend schema grows them.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/utils/formatters.dart';

/// account_type values from the backend: ASSET, LIABILITY, EQUITY, REVENUE, EXPENSE.
enum AccountType {
  asset,
  liability,
  equity,
  revenue,
  expense;

  String get apiValue => name.toUpperCase();

  static AccountType fromApi(String? v) => AccountType.values.firstWhere(
    (e) => e.apiValue == (v?.toUpperCase() ?? ''),
    orElse: () => asset,
  );

  String get displayLabel => switch (this) {
    AccountType.asset => 'Asset',
    AccountType.liability => 'Liability',
    AccountType.equity => 'Equity',
    AccountType.revenue => 'Income',
    AccountType.expense => 'Expense',
  };

  IconData get icon => switch (this) {
    AccountType.asset => Icons.account_balance_wallet_outlined,
    AccountType.liability => Icons.credit_card_outlined,
    AccountType.equity => Icons.diamond_outlined,
    AccountType.revenue => Icons.trending_up_rounded,
    AccountType.expense => Icons.trending_down_rounded,
  };

  bool get debitIncreases =>
      this == AccountType.asset || this == AccountType.expense;

  String get statementGroup => switch (this) {
    AccountType.asset ||
    AccountType.liability ||
    AccountType.equity => 'Balance Sheet',
    AccountType.revenue || AccountType.expense => 'Profit & Loss',
  };
}

/// Account — matches AccountResponse from the backend.
@immutable
class Account extends BaseModel {
  const Account({
    required this.id,
    required this.name,
    this.code = '',
    this.accountType = AccountType.asset,
    this.accountGroup,
    this.parentId,
    this.openingBalance = 0,
    this.currentBalance = 0,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  @override
  final String id;
  final String name;
  final String code;
  final AccountType accountType;
  final String? accountGroup;
  final String? parentId;
  final double openingBalance;
  final double currentBalance;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  bool get isRoot => parentId == null || parentId!.isEmpty;

  @override
  Account fromJson(Map<String, dynamic> json) => Account(
    id: (json['id'] ?? '').toString(),
    name: json['name'] as String? ?? '',
    code: json['code'] as String? ?? '',
    accountType: AccountType.fromApi(json['account_type'] as String?),
    accountGroup: json['account_group'] as String?,
    parentId: (json['parent_id'] as dynamic)?.toString(),
    openingBalance: parseDecimal(json['opening_balance']),
    currentBalance: parseDecimal(json['current_balance']),
    isActive: json['is_active'] as bool? ?? true,
    createdAt: json['created_at'] as String?,
    updatedAt: json['updated_at'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    'code': code,
    'account_type': accountType.apiValue,
    if (accountGroup != null && accountGroup!.isNotEmpty)
      'account_group': accountGroup,
    if (parentId != null && parentId!.isNotEmpty) 'parent_id': parentId,
    'opening_balance': openingBalance.toStringAsFixed(2),
  };

  Map<String, dynamic> toUpdateJson() => {
    'name': name,
    'code': code,
    'account_group': accountGroup,
    'parent_id': parentId,
    'opening_balance': openingBalance.toStringAsFixed(2),
    'is_active': isActive,
  };

  Account copyWith({
    String? id,
    String? name,
    String? code,
    AccountType? accountType,
    String? accountGroup,
    String? parentId,
    double? openingBalance,
    double? currentBalance,
    bool? isActive,
  }) => Account(
    id: id ?? this.id,
    name: name ?? this.name,
    code: code ?? this.code,
    accountType: accountType ?? this.accountType,
    accountGroup: accountGroup ?? this.accountGroup,
    parentId: parentId ?? this.parentId,
    openingBalance: openingBalance ?? this.openingBalance,
    currentBalance: currentBalance ?? this.currentBalance,
    isActive: isActive ?? this.isActive,
  );
}

/// A node in the account tree, holding an account and its children.
@immutable
class AccountNode {
  const AccountNode({required this.account, this.children = const []});
  final Account account;
  final List<AccountNode> children;

  /// Depth-aware current balance: a parent's balance is the sum of itself
  /// plus its descendants. The backend stores each account's own balance, so
  /// aggregation is done client-side for the tree display.
  double get totalBalance =>
      account.currentBalance +
      children.fold(0.0, (sum, c) => sum + c.totalBalance);

  /// True if this node or any descendant matches [test].
  bool anyMatch(bool Function(Account) test) =>
      test(account) || children.any((c) => c.anyMatch(test));
}

/// Builds a forest of [AccountNode]s from a flat list of accounts, grouping
/// by `parentId`. Roots are accounts with no parent. Returns roots sorted by
/// code, each subtree sorted by code. Children whose parent is missing (e.g.
/// parent was deleted) are treated as roots to avoid silent data loss.
List<AccountNode> buildAccountTree(List<Account> accounts) {
  final byId = {for (final a in accounts) a.id: a};
  final childrenMap = <String, List<Account>>{};
  final roots = <Account>[];

  for (final a in accounts) {
    if (a.isRoot || byId[a.parentId] == null) {
      roots.add(a);
    } else {
      childrenMap.putIfAbsent(a.parentId!, () => []).add(a);
    }
  }

  int byCode(Account a, Account b) => a.code.compareTo(b.code);

  AccountNode build(Account a) {
    final kids = (childrenMap[a.id] ?? [])..sort(byCode);
    return AccountNode(account: a, children: kids.map(build).toList());
  }

  roots.sort(byCode);
  return roots.map(build).toList();
}

/// Detects whether setting [newParentId] on [accountId] would create a cycle
/// (i.e. the new parent is the account itself or one of its descendants).
/// Uses the existing [accounts] list to walk the parent chain.
bool wouldCreateCycle(
  List<Account> accounts,
  String accountId,
  String? newParentId,
) {
  if (newParentId == null || newParentId.isEmpty) return false;
  if (newParentId == accountId) return true;
  final byId = {for (final a in accounts) a.id: a};
  String? cursor = newParentId;
  while (cursor != null && byId[cursor] != null) {
    if (cursor == accountId) return true;
    cursor = byId[cursor]!.parentId;
  }
  return false;
}
