/// Repository for /masters/contacts.
library;

import 'package:apexbooks/core/api/base_repository.dart';
import '../models/contact.dart';

class ContactRepository extends BaseRepository<Contact> {
  ContactRepository(super.dio, super.cache);

  @override
  String get path => '/masters/contacts';
  @override
  String get cachePrefix => 'contacts';
  @override
  Contact parseOne(Map<String, dynamic> json) =>
      const Contact(id: '', name: '').fromJson(json);
}
