/// Read-only repository for /masters/tax-templates.
library;

import 'package:dio/dio.dart';
import 'package:apexbooks/core/api/base_repository.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import '../models/tax_template.dart';

class TaxTemplateRepository extends BaseRepository<TaxTemplate> {
  TaxTemplateRepository(Dio dio, CacheService cache) : super(dio, cache);

  @override
  String get path => '/masters/tax-templates';
  @override
  String get cachePrefix => 'tax-templates';
  @override
  TaxTemplate parseOne(Map<String, dynamic> json) =>
      const TaxTemplate(id: '').fromJson(json);
}
