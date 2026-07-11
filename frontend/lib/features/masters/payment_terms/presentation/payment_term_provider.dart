/// Payment Term provider — loads the read-only list.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import '../data/models/payment_term.dart';
import '../data/repositories/payment_term_repository.dart';

final paymentTermRepositoryProvider = Provider<PaymentTermRepository>((ref) {
  return PaymentTermRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheServiceProvider),
  );
});

final paymentTermListProvider = FutureProvider<List<PaymentTerm>>((ref) async {
  final repo = ref.watch(paymentTermRepositoryProvider);
  final result = await repo.list(const ListQuery(limit: 50));
  return switch (result) {
    Loading<Paged<PaymentTerm>>() => const [],
    Success<Paged<PaymentTerm>>(:final value) => value.items,
    Failure(:final error) => throw error,
  };
});
