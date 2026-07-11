/// Recent items tracking. Every module records recently accessed records here
/// so the quick-access panel can show them.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A recently accessed record.
@immutable
class RecentItem {
  const RecentItem({
    required this.id,
    required this.title,
    required this.category,
    required this.route,
    this.subtitle,
    this.icon,
  });

  final String id;
  final String title;
  final String category;
  final String route;
  final String? subtitle;
  final String? icon; // icon name from the design system

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecentItem && id == other.id && category == other.category;

  @override
  int get hashCode => Object.hash(id, category);
}

/// Manages the list of recent items (max [maxItems]).
class RecentItemsNotifier extends StateNotifier<List<RecentItem>> {
  RecentItemsNotifier() : super(const []);

  static const int maxItems = 20;

  void add(RecentItem item) {
    state = [item, ...state.where((i) => i != item)].take(maxItems).toList();
  }

  void remove(RecentItem item) {
    state = state.where((i) => i != item).toList();
  }

  void clear() => state = const [];
}

final recentItemsProvider =
    StateNotifierProvider<RecentItemsNotifier, List<RecentItem>>(
      (ref) => RecentItemsNotifier(),
    );
