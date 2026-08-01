/// Expense service — API communication for expense management.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';

/// Parses monetary amounts from backend responses, tolerant of:
///   - null / missing (returns 0)
///   - num (int or double)
///   - Decimal-as-string ("150000.0000")
///   - Indian-style comma formatting ("1,50,000.00")
double _amount(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  final cleaned = value.toString().replaceAll(',', '');
  return double.tryParse(cleaned) ?? 0;
}

class ExpenseRecord {
  const ExpenseRecord({
    required this.id,
    required this.number,
    required this.date,
    required this.amount,
    required this.total,
    required this.status,
    this.category,
    this.vendor,
    this.description,
  });

  final String id;
  final String number;
  final String date;
  final double amount;
  final double total;
  final String status;
  final String? category;
  final String? vendor;
  final String? description;

  factory ExpenseRecord.fromJson(Map<String, dynamic> json) => ExpenseRecord(
    id: (json['id'] ?? '').toString(),
    number: json['expense_number'] as String? ?? '',
    date: json['expense_date'] as String? ?? '',
    amount: _amount(json['amount']),
    total: _amount(json['total']),
    status: json['status'] as String? ?? 'DRAFT',
    category: json['category_name'] as String?,
    vendor: json['vendor_name'] as String?,
    description: json['description'] as String?,
  );
}

class ExpenseService {
  ExpenseService(this._dio);
  final Dio _dio;

  Future<Result<List<ExpenseRecord>>> list() => guardDio(() async {
    final response = await _dio.get(
      '/expenses',
      queryParameters: {'limit': 100},
    );
    return (response.data as List)
        .map((row) => ExpenseRecord.fromJson(row as Map<String, dynamic>))
        .toList();
  });

  Future<Result<ExpenseRecord>> create(Map<String, dynamic> body) =>
      guardDio(() async {
        final response = await _dio.post('/expenses', data: body);
        return ExpenseRecord.fromJson(response.data as Map<String, dynamic>);
      });

  Future<Result<ExpenseRecord>> action(String id, String action) =>
      guardDio(() async {
        final response = await _dio.post('/expenses/$id/$action');
        return ExpenseRecord.fromJson(response.data as Map<String, dynamic>);
      });
}

final expenseServiceProvider = Provider<ExpenseService>(
  (ref) => ExpenseService(ref.watch(apiClientProvider)),
);

final expenseListProvider = FutureProvider.autoDispose<List<ExpenseRecord>>((
  ref,
) async {
  final result = await ref.watch(expenseServiceProvider).list();
  return switch (result) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => <ExpenseRecord>[],
  };
});
