/// Favorites provider. Users can pin customers, invoices, reports, etc., and
/// the pinned items appear in the quick-access panel.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A model for any favorited record.
@immutable
class FavoriteItem {
  const FavoriteItem({
    required this.id,
    required this.title,
    required this.category,
    required this.route,
    this.subtitle,
  });

  final String id;
  final String title;
  final String category;
  final String route;
  final String? subtitle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteItem && id == other.id && category == other.category;

  @override
  int get hashCode => Object.hash(id, category);
}

/// Notifier for the set of favorites.
class FavoritesNotifier extends StateNotifier<List<FavoriteItem>> {
  FavoritesNotifier() : super(const []);

  bool isFavorite(String id, String category) =>
      state.any((f) => f.id == id && f.category == category);

  void toggle(FavoriteItem item) {
    if (isFavorite(item.id, item.category)) {
      state = state.where((f) => f != item).toList();
    } else {
      state = [...state, item];
    }
  }

  void add(FavoriteItem item) {
    if (!isFavorite(item.id, item.category)) {
      state = [...state, item];
    }
  }

  void remove(FavoriteItem item) {
    state = state.where((f) => f != item).toList();
  }

  void clear() => state = const [];
}

/// Provider for [FavoritesNotifier].
final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<FavoriteItem>>(
      (ref) => FavoritesNotifier(),
    );
