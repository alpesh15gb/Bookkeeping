import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/result/result.dart';

import '../data/models/contact.dart';
import '../data/repositories/contact_repository.dart';

/// Searches the complete server-side party master while retaining local
/// results as a resilient fallback. Results match name, GSTIN, phone or email,
/// with names beginning with the typed text ranked first.
Future<Iterable<Contact>> searchContactOptions({
  required ContactRepository repository,
  required List<Contact> localContacts,
  required ContactType type,
  required String query,
  int limit = 20,
}) async {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    final initial = [...localContacts]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return initial.take(limit);
  }

  bool matches(Contact contact) =>
      contact.name.toLowerCase().contains(normalized) ||
      (contact.gstin ?? '').toLowerCase().contains(normalized) ||
      (contact.phone ?? '').toLowerCase().contains(normalized) ||
      (contact.email ?? '').toLowerCase().contains(normalized);

  final localMatches = localContacts.where(matches).toList();
  final result = await repository.list(
    ListQuery(
      search: query.trim(),
      limit: limit,
      extra: {'contact_type': type.apiValue},
    ),
  );

  final byId = <String, Contact>{};
  for (final contact in [...?result.dataOrNull?.items, ...localMatches]) {
    byId[contact.id] = contact;
  }
  final matchesFromAllSources = byId.values.where(matches).toList()
    ..sort((a, b) {
      final aStarts = a.name.toLowerCase().startsWith(normalized);
      final bStarts = b.name.toLowerCase().startsWith(normalized);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return matchesFromAllSources.take(limit);
}
