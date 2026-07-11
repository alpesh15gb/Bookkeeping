/// Tax Template provider — loads the read-only list.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import '../data/models/tax_template.dart';
import '../data/repositories/tax_template_repository.dart';

final taxTemplateRepositoryProvider = Provider<TaxTemplateRepository>((ref) {
  return TaxTemplateRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheServiceProvider),
  );
});

/// Simple state: loading, loaded list, or error.
final taxTemplateListProvider = FutureProvider<List<TaxTemplate>>((ref) async {
  final repo = ref.watch(taxTemplateRepositoryProvider);
  final result = await repo.list(const ListQuery(limit: 50));
  return switch (result) {
    Loading<Paged<TaxTemplate>>() => const [],
    Success<Paged<TaxTemplate>>(:final value) => value.items,
    Failure(:final error) => throw error,
  };
});
