/// Payment providers — list, detail, form.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/payment_models.dart';
import '../services/payment_service.dart';
import '../services/allocation_service.dart';
import '../services/payment_validation_service.dart';
import 'payment_form_notifier.dart';
import 'payment_form_state.dart';

final paymentFormProvider =
    StateNotifierProvider.autoDispose<PaymentFormNotifier, PaymentFormState>((
      ref,
    ) {
      return PaymentFormNotifier(
        ref.watch(paymentServiceProvider),
        const AllocationService(),
        const PaymentValidationService(),
      );
    });

final paymentDetailProvider = FutureProvider.autoDispose
    .family<Payment, String>((ref, id) async {
      final service = ref.watch(paymentServiceProvider);
      final result = await service.get(id);
      return switch (result) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception('Unexpected result type'),
      };
    });

final paymentListProvider = FutureProvider.autoDispose
    .family<List<PaymentListItem>, int>((ref, page) async {
      final service = ref.watch(paymentServiceProvider);
      final result = await service.list(page: page);
      return switch (result) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception('Unexpected result type'),
      };
    });
