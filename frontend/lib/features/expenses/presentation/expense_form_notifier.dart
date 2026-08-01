/// Expense form notifier — Riverpod state management for expense creation.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../services/expense_service.dart';

/// Immutable state for the expense form.
class ExpenseFormState {
  const ExpenseFormState({
    this.categoryId,
    this.accountId,
    this.date = '',
    this.vendor = '',
    this.description = '',
    this.reference = '',
    this.placeOfSupply = '',
    this.amount = 0,
    this.gstRate = 0,
    this.total = 0,
    this.saving = false,
    this.error,
    this.receiptPath,
  });

  final String? categoryId;
  final String? accountId;
  final String date;
  final String vendor;
  final String description;
  final String reference;
  final String placeOfSupply;
  final double amount;
  final double gstRate;
  final double total;
  final bool saving;
  final String? error;
  final String? receiptPath;

  double get gstAmount => amount * gstRate / 100;
  double get taxableAmount => amount;
  double get totalAmount => amount + gstAmount;

  ExpenseFormState copyWith({
    String? categoryId,
    String? accountId,
    String? date,
    String? vendor,
    String? description,
    String? reference,
    String? placeOfSupply,
    double? amount,
    double? gstRate,
    double? total,
    bool? saving,
    String? error,
    String? receiptPath,
    bool clearError = false,
  }) {
    return ExpenseFormState(
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      date: date ?? this.date,
      vendor: vendor ?? this.vendor,
      description: description ?? this.description,
      reference: reference ?? this.reference,
      placeOfSupply: placeOfSupply ?? this.placeOfSupply,
      amount: amount ?? this.amount,
      gstRate: gstRate ?? this.gstRate,
      total: total ?? this.total,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
      receiptPath: receiptPath ?? this.receiptPath,
    );
  }
}

/// Notifier for expense form state.
class ExpenseFormNotifier extends StateNotifier<ExpenseFormState> {
  ExpenseFormNotifier(this._service) : super(const ExpenseFormState()) {
    final now = DateTime.now();
    state = state.copyWith(
      date:
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    );
  }

  final ExpenseService _service;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _setState(ExpenseFormState newState) {
    if (!_disposed) state = newState;
  }

  void setCategory(String? id) => _setState(state.copyWith(categoryId: id));
  void setAccount(String? id) => _setState(state.copyWith(accountId: id));
  void setDate(String d) => _setState(state.copyWith(date: d));
  void setVendor(String v) => _setState(state.copyWith(vendor: v));
  void setDescription(String d) => _setState(state.copyWith(description: d));
  void setReference(String r) => _setState(state.copyWith(reference: r));
  void setPlaceOfSupply(String p) =>
      _setState(state.copyWith(placeOfSupply: p));
  void setAmount(double a) => _setState(state.copyWith(amount: a));
  void setGstRate(double r) => _setState(state.copyWith(gstRate: r));
  void setReceiptPath(String? p) => _setState(state.copyWith(receiptPath: p));

  Future<bool> save() async {
    if (state.saving) return false;

    if (state.categoryId == null ||
        state.amount <= 0 ||
        DateTime.tryParse(state.date) == null) {
      _setState(
        state.copyWith(
          error:
              'Select a category and enter a valid date and positive amount.',
        ),
      );
      return false;
    }
    if (state.placeOfSupply.isNotEmpty &&
        !RegExp(r'^\d{2}$').hasMatch(state.placeOfSupply)) {
      _setState(
        state.copyWith(
          error: 'Place of supply must be a two-digit GST state code.',
        ),
      );
      return false;
    }

    _setState(state.copyWith(saving: true, clearError: true));

    final result = await _service.create({
      'expense_category_id': state.categoryId,
      if (state.accountId != null) 'bank_account_id': state.accountId,
      'expense_date': state.date,
      if (state.vendor.trim().isNotEmpty) 'vendor_name': state.vendor.trim(),
      if (state.description.trim().isNotEmpty)
        'description': state.description.trim(),
      'amount': state.amount,
      'gst_rate': state.gstRate,
      if (state.placeOfSupply.isNotEmpty)
        'place_of_supply_state_code': state.placeOfSupply,
      if (state.reference.trim().isNotEmpty)
        'reference_number': state.reference.trim(),
    });

    if (_disposed) return false;
    _setState(state.copyWith(saving: false));
    switch (result) {
      case Failure<ExpenseRecord>(:final error):
        _setState(state.copyWith(error: error.message));
        return false;
      case Success<ExpenseRecord>():
        return true;
      case Loading<ExpenseRecord>():
        return false;
    }
  }
}

final expenseFormProvider =
    StateNotifierProvider.autoDispose<ExpenseFormNotifier, ExpenseFormState>((
      ref,
    ) {
      final service = ref.watch(expenseServiceProvider);
      return ExpenseFormNotifier(service);
    });
