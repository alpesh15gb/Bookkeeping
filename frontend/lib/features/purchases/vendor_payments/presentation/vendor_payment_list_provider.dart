/// Vendor payment list provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/vendor_payment.dart';
import '../services/vendor_payment_service.dart';

final vendorPaymentListProvider =
    FutureProvider.autoDispose<List<VendorPayment>>((ref) async {
      final res = await ref.watch(vendorPaymentServiceProvider).list();
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });
