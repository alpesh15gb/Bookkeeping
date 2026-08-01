/// Read-only repository for /masters/tax-templates.
library;

import 'package:apexbooks/core/api/base_repository.dart';
import '../models/tax_template.dart';

class TaxTemplateRepository extends BaseRepository<TaxTemplate> {
  TaxTemplateRepository(super.dio, super.cache);

  @override
  String get path => '/masters/tax-templates';
  @override
  String get cachePrefix => 'tax-templates';
  @override
  TaxTemplate parseOne(Map<String, dynamic> json) =>
      const TaxTemplate(id: '').fromJson(json);
}
