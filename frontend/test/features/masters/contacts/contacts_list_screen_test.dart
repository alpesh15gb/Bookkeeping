// Widget integration test for Contact list screen — uses a mocked API client
// and repository so the test runs offline without hitting the real backend.
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
import 'package:apexbooks/features/masters/contacts/data/repositories/contact_repository.dart';
import 'package:apexbooks/features/masters/contacts/presentation/contact_controller.dart';
import 'package:apexbooks/features/masters/contacts/presentation/contact_list_screen.dart';

class _FakeDioAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode({
      'items': [
        {'id': '1', 'name': 'Alpha Co', 'contact_type': 'CUSTOMER'},
        {'id': '2', 'name': 'Beta Inc', 'contact_type': 'VENDOR'},
      ],
      'total': 2,
      'page': 1,
      'limit': 20,
    });
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
  testWidgets('ContactListScreen renders scaffold and title', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.apexbooks.in/api/v1'));
    dio.httpClientAdapter = _FakeDioAdapter();
    final logger = LoggerService();
    final cache = CacheService(logger);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(dio),
          contactRepositoryProvider.overrideWithValue(
            ContactRepository(dio, cache),
          ),
        ],
        child: MaterialApp(
          theme: apexLightTheme(),
          home: const ContactListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.byType(ContactListScreen), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
  });
}
