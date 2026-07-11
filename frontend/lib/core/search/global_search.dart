/// Global search framework. Each feature registers a [SearchProvider] that
/// knows how to query its backend for a search term; the [GlobalSearchService]
/// aggregates them so the command palette / search overlay can show unified
/// results across customers, invoices, products, ledger, payments, journals.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../result/result.dart';

/// A single search result with enough context to navigate to it.
@immutable
class SearchResult {
  const SearchResult({
    required this.id,
    required this.title,
    required this.category,
    this.subtitle,
    this.icon,
    this.route,
  });

  final String id;
  final String title;
  final String category;
  final String? subtitle;
  final IconData? icon;
  final String? route;
}

/// Contract a feature implements to plug into global search.
abstract class SearchProvider {
  /// The display category label (e.g. 'Customers', 'Invoices').
  String get category;

  /// Returns up to [limit] results matching [query].
  Future<Result<List<SearchResult>>> search(String query, {int limit = 5});
}

/// Aggregates registered [SearchProvider]s and runs a fan-out search across
/// all of them, returning merged + category-grouped results.
class GlobalSearchService {
  GlobalSearchService(this._providers);
  final List<SearchProvider> _providers;

  /// Runs [query] across every registered provider and merges the results,
  /// grouped by category. Failures in a single provider don't fail the whole
  /// search — that provider simply contributes no results.
  Future<Map<String, List<SearchResult>>> search(String query) async {
    if (query.trim().isEmpty) return {};
    final results = <String, List<SearchResult>>{};
    final futures = _providers.map((p) async {
      final r = await p.search(query);
      if (r is Success<List<SearchResult>>) {
        results[p.category] = r.value;
      }
    });
    await Future.wait(futures);
    return results;
  }
}

/// Provider registry — features add their [SearchProvider] here during boot.
final searchProvidersProvider = StateProvider<List<SearchProvider>>(
  (ref) => const [],
);

/// Provider for [GlobalSearchService], built from the registered providers.
final globalSearchServiceProvider = Provider<GlobalSearchService>((ref) {
  return GlobalSearchService(ref.watch(searchProvidersProvider));
});
