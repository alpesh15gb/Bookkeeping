/// Product controller.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import '../data/models/product.dart';
import '../data/repositories/product_repository.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheServiceProvider),
  );
});

final productControllerProvider =
    StateNotifierProvider<ProductController, ListState>((ref) {
      return ProductController(
        ref.watch(productRepositoryProvider),
        ref.watch(notificationServiceProvider),
      );
    });

class ProductController extends BaseCrudController<Product> {
  ProductController(ProductRepository repo, NotificationService notif)
    : super(repo, notif);
}
