/// Repository for /masters/contacts.
library;

import 'package:dio/dio.dart';
import 'package:apexbooks/core/api/base_repository.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import '../models/contact.dart';

class ContactRepository extends BaseRepository<Contact> {
  ContactRepository(Dio dio, CacheService cache) : super(dio, cache);

  @override
  String get path => '/masters/contacts';
  @override
  String get cachePrefix => 'contacts';
  @override
  Contact parseOne(Map<String, dynamic> json) =>
      const Contact(id: '', name: '').fromJson(json);
}
