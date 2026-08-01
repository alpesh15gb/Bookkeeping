/// Repository for /masters/banking-profiles.
library;

import 'package:apexbooks/core/api/base_repository.dart';
import '../models/banking_profile.dart';

class BankingProfileRepository extends BaseRepository<BankingProfile> {
  BankingProfileRepository(super.dio, super.cache);

  @override
  String get path => '/masters/banking-profiles';
  @override
  String get cachePrefix => 'banking-profiles';
  @override
  BankingProfile parseOne(Map<String, dynamic> json) =>
      const BankingProfile(id: '').fromJson(json);
}
