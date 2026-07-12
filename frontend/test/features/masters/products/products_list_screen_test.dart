// Widget integration test for Product list screen — uses a mocked API client
// returning the REAL backend shape: a flat JSON array (not an envelope).
// This validates that BaseRepository + parsePaged handle the ApexBooks
// masters list contract (List[ProductResponse]) correctly.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/logging/logger_service.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/theme/app_theme.dart';
import 'package:apexbooks/features/masters/products/data/repositories/product_repository.dart';
import 'package:apexbooks/features/masters/products/presentation/product_controller.dart';
import 'package:apexbooks/features/masters/products/presentation/product_list_screen.dart';

class _FlatArrayDioAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Real backend returns a bare JSON array: List[ProductResponse]
    final body = jsonEncode([
      {
        'id': 'p-1',
        'tenant_id': 't-1',
        'name': 'Steel Rod 12mm',
        'sku': 'SR-12',
        'hsn_sac': '72141000',
        'product_type': 'GOODS',
        'uom': 'PCS',
        'sales_price': '150.00',
        'purchase_price': '120.00',
        'gst_rate': '18.00',
        'opening_stock': '100.00',
        'current_stock': '5.00',
        'reorder_level': '20.00',
        'is_active': true,
        'created_at': '2025-07-01T10:00:00+00:00',
        'updated_at': '2025-07-01T10:00:00+00:00',
      },
      {
        'id': 'p-2',
        'tenant_id': 't-1',
        'name': 'Audit Service',
        'sku': null,
        'hsn_sac': '998321',
        'product_type': 'SERVICE',
        'uom': 'HRS',
        'sales_price': '5000.00',
        'purchase_price': '0.00',
        'gst_rate': '18.00',
        'opening_stock': '0.00',
        'current_stock': '0.00',
        'reorder_level': '0.00',
        'is_active': true,
        'created_at': '2025-07-01T10:00:00+00:00',
        'updated_at': '2025-07-01T10:00:00+00:00',
      },
    ]);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

void main() {
  testWidgets(
    'ProductListScreen renders scaffold, title and rows from flat-array API',
    (tester) async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.apexbooks.in/api/v1'));
      dio.httpClientAdapter = _FlatArrayDioAdapter();
      final logger = LoggerService();
      final cache = CacheService(logger);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(dio),
            productRepositoryProvider.overrideWithValue(
              ProductRepository(dio, cache),
            ),
          ],
          child: MaterialApp(
            theme: apexLightTheme(),
            home: const ProductListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(ProductListScreen), findsOneWidget);
      expect(find.text('Products'), findsOneWidget);
      // Rows parsed from the flat array appear.
      expect(find.text('Steel Rod 12mm'), findsOneWidget);
      expect(find.text('Audit Service'), findsOneWidget);
    },
  );
}
